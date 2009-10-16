/*
 * Copyright 2009 Jiro Nishiguchi <jiro@cpan.org>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#ifdef _WIN32
/* avoid to define duplicate definition of uid_t/gid_t in perl/CORE.h */
#define uid_t _uid_t
#define gid_t _gid_t
#endif
#include "httpd.h"
#include "http_log.h"
#include "http_config.h"
#include "http_protocol.h"
#include "util_script.h"
#include "ap_config.h"
#include "ap_mpm.h"
#include "apr_buckets.h"
#include "apr_strings.h"
#include "apr_hash.h"

#ifdef _WIN32
/* use perl's uid_t/gid_t. disable apr's macros. */
#undef uid_t
#undef gid_t
#undef exit
#endif

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#define NEED_eval_pv
#define NEED_newRV_noinc
#define NEED_sv_2pv_flags
#include "ppport.h"

#ifdef _WIN32
/* no use perl compatible macros. it break apr's structure. ex: bucket->link */
#undef link
#undef read
#endif

#define PSGI_HANDLER_NAME "psgi"

#ifdef DEBUG
#define TRACE(...) ap_log_error(APLOG_MARK, APLOG_NOERRNO|APLOG_NOTICE, 0, NULL, __VA_ARGS__)
#endif

module AP_MODULE_DECLARE_DATA psgi_module;

typedef struct {
    char *file;
    char *location;
} psgi_dir_config;

static PerlInterpreter *perlinterp = NULL;

static apr_hash_t *app_mapping = NULL;

static apr_array_header_t *psgi_apps = NULL;

static void server_error(request_rec *r, const char *fmt, ...)
{
    va_list argp;
    const char *msg;
    va_start(argp, fmt);
    msg = apr_pvsprintf(r->pool, fmt, argp);
    va_end(argp);
    ap_log_error(APLOG_MARK, APLOG_NOERRNO|APLOG_ERR, 0, r->server, "%s", msg);
}

EXTERN_C void xs_init (pTHX);

EXTERN_C void boot_DynaLoader (pTHX_ CV* cv);

XS(ModPSGI_exit);
XS(ModPSGI_exit)
{
    dXSARGS;
    croak("exit");
    XSRETURN(0);
}

XS(ModPSGI_Input_read);
XS(ModPSGI_Input_read)
{
    dXSARGS;
    SV *self = ST(0);
    SV *buf = ST(1);
    request_rec *r = (request_rec *) mg_find(SvRV(self), PERL_MAGIC_ext)->mg_obj;
    apr_size_t len = SvIV(ST(2));
    apr_size_t offset = items >= 4 ? SvIV(ST(3)) : 0;
    apr_status_t rv;
    apr_bucket_brigade *bb;
    apr_bucket *bucket;
    int eos = 0;
    SV *ret;
    dXSTARG;

    ret = newSVpv("", 0);
    bb = apr_brigade_create(r->pool, r->connection->bucket_alloc);
    rv = ap_get_brigade(r->input_filters, bb, AP_MODE_READBYTES, APR_BLOCK_READ, len);
    if (rv != APR_SUCCESS) {
        ST(0) = &PL_sv_undef;
        XSRETURN(1);
    }

    for (bucket = APR_BRIGADE_FIRST(bb);
            bucket != APR_BRIGADE_SENTINEL(bb);
            bucket = APR_BUCKET_NEXT(bucket)) {
        const char *bbuf;
        apr_size_t blen;
        if (APR_BUCKET_IS_EOS(bucket)) {
            eos = 1;
            break;
        }
        if (APR_BUCKET_IS_METADATA(bucket)) {
            continue;
        }
        apr_bucket_read(bucket, &bbuf, &blen, APR_BLOCK_READ);
        sv_catpvn(ret, bbuf, blen);
    }

    sv_setsv(buf, ret);
    ST(0) = sv_2mortal(newSViv(SvCUR(buf)));
    XSRETURN(1);
}

XS(ModPSGI_Errors_print);
XS(ModPSGI_Errors_print)
{
    dXSARGS;
    SV *self = ST(0);
    SV *msg  = ST(1);
    dXSTARG;
    request_rec *r = (request_rec *) mg_find(SvRV(self), PERL_MAGIC_ext)->mg_obj;
    ap_log_error(APLOG_MARK, APLOG_NOERRNO|APLOG_ERR, 0, r->server, "%s", SvPV_nolen(msg));
    ST(0) = newSViv(1);
    XSRETURN(1);
}

EXTERN_C void
xs_init(pTHX)
{
    char *file = __FILE__;
    dXSUB_SYS;

    newXS("DynaLoader::boot_DynaLoader", boot_DynaLoader, file);
    newXS("ModPSGI::exit", ModPSGI_exit, file);
    newXSproto("ModPSGI::Input::read", ModPSGI_Input_read, file, "$$$;$");
    newXSproto("ModPSGI::Errors::print", ModPSGI_Errors_print, file, "$$");
}

static int copy_env(void *rec, const char *key, const char *val)
{
    dTHX;
    HV *env = (HV *) rec;
    hv_store(env, key, strlen(key), newSVpv(val, 0), 0);
    return 1;
}

static SV *make_env(request_rec *r, psgi_dir_config *c)
{
    dTHX;
    HV *env;
    AV *version;
    char *url_scheme, *script_name, *vpath, *path_info;
    SV *input, *errors;

    env = newHV();

    ap_add_cgi_vars(r);
    ap_add_common_vars(r);

    /* fix SCRIPT_NAME & PATH_INFO */
    if (c->location == NULL || strcmp(c->location, "/") == 0) {
        script_name = "";
    } else {
        script_name = c->location;
    }
    vpath = apr_pstrcat(r->pool,
            apr_table_get(r->subprocess_env, "SCRIPT_NAME"),
            apr_table_get(r->subprocess_env, "PATH_INFO"),
            NULL);
    path_info = &vpath[strlen(script_name)];
    apr_table_set(r->subprocess_env, "PATH_INFO", path_info);
    apr_table_set(r->subprocess_env, "SCRIPT_NAME", script_name);

    apr_table_do(copy_env, env, r->subprocess_env, NULL);

    version = newAV();
    av_push(version, newSViv(1));
    av_push(version, newSViv(0));
    hv_store(env, "psgi.version", 12, newRV_inc((SV *) version), 0);

    url_scheme = apr_table_get(r->subprocess_env, "HTTPS") == NULL ?  "http" : "https";
    hv_store(env, "psgi.url_scheme", 15, newSVpv(url_scheme, 0), 0);

    input = newRV_noinc(newSV(0));
    sv_magic(SvRV(input), NULL, PERL_MAGIC_ext, NULL, 0);
    mg_find(SvRV(input), PERL_MAGIC_ext)->mg_obj = (void *) r;
    sv_bless(input, gv_stashpv("ModPSGI::Input", 1));
    hv_store(env, "psgi.input", 10, input, 0);

    errors = newRV_noinc(newSV(0));
    sv_magic(SvRV(errors), NULL, PERL_MAGIC_ext, NULL, 0);
    mg_find(SvRV(errors), PERL_MAGIC_ext)->mg_obj = (void *) r;
    sv_bless(errors, gv_stashpv("ModPSGI::Errors", 1));
    hv_store(env, "psgi.errors", 11, errors, 0);

    hv_store(env, "psgi.multithread", 16, newSViv(0), 0);
    hv_store(env, "psgi.multiprocess", 17, newSViv(1), 0);
    hv_store(env, "psgi.run_once", 13, newSViv(1), 0);
    hv_store(env, "psgi.nonblocking", 16, newSViv(0), 0);

    return newRV_inc((SV *) env);
}

static SV *run_app(request_rec *r, SV *app, SV *env)
{
    dTHX;
    int count;
    SV *res;
    dSP;
    ENTER;
    SAVETMPS;
    PUSHMARK(SP) ;
    XPUSHs(sv_2mortal(env));
    PUTBACK;

    count = call_sv(app, G_EVAL|G_SCALAR);
    SPAGAIN;
    if (SvTRUE(ERRSV)) {
        res = NULL;
        server_error(r, "%s", SvPV_nolen(ERRSV));
        POPs;
    } else if (count > 0) {
        res = POPs;
        SvREFCNT_inc(res);
    } else {
        res = NULL;
    }
    PUTBACK;
    FREETMPS;
    LEAVE;
    return res;
}

static int output_status(request_rec *r, SV *status)
{
    dTHX;
    int s = SvIV(status);
    if (s < 100) {
        server_error(r, "invalid response status %d", s);
        return HTTP_INTERNAL_SERVER_ERROR;
    }
    r->status = s;
    return OK;
}

static int output_headers(request_rec *r, AV *headers)
{
    dTHX;
    SV *key_sv, *val_sv;
    char *key;

    r->content_type = NULL;
    while (av_len(headers) > -1) {
        key_sv = av_shift(headers);
        val_sv = av_shift(headers);
        if (key_sv == NULL || val_sv == NULL) break;
        key = SvPV_nolen(key_sv);
        if (strcmp(key, "Content-Type") == 0) {
            r->content_type = apr_pstrdup(r->pool, SvPV_nolen(val_sv));
        } else if (strcmp(key, "Content-Length") == 0) {
            ap_set_content_length(r, SvIV(val_sv));
        } else if (strcmp(key, "Status") == 0) {
            server_error(r, "headers must not contain a Status");
            return HTTP_INTERNAL_SERVER_ERROR;
        } else {
            apr_table_add(r->headers_out, key, SvPV_nolen(val_sv));
        }
    }
    return OK;
}

static int respond_to(SV *obj, const char *method)
{
    dTHX;
    int res;
    dSP;
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    XPUSHs(obj);
    XPUSHs(sv_2mortal(newSVpv(method, 0)));
    PUTBACK;

    call_method("can", G_SCALAR);
    SPAGAIN;
    res = SvROK(POPs);
    PUTBACK;
    FREETMPS;
    LEAVE;
    return res;
}

static int output_body_ary(request_rec *r, AV *bodys)
{
    dTHX;
    SV **body;
    I32 i;
    I32 lastidx;
    char *buf;
    STRLEN len;
    apr_off_t clen = 0;

    lastidx = av_len(bodys);
    for (i = 0; i <= lastidx; i++) {
        body = av_fetch(bodys, i, 0);
        if (SvOK(*body)) {
            buf = SvPV(*body, len);
            ap_rwrite(buf, len, r);
            clen += len;
        }
    }
    if (clen > 0) {
        ap_set_content_length(r, clen);
    }
    return OK;
}

static int output_body_obj(request_rec *r, SV *obj, int type)
{
    dTHX;
    SV *buf_sv, *rs;
    apr_off_t clen = 0;
    STRLEN len;
    dSP;
    char *buf;
    int count;

    if (type == SVt_PVMG && !respond_to(obj, "getline")) {
        server_error(r, "response body object must be able to getline");
        return HTTP_INTERNAL_SERVER_ERROR;
    }

    ENTER;
    SAVETMPS;
    SAVESPTR(PL_rs);
    PL_rs = newRV_inc(newSViv(AP_IOBUFSIZE));
    while (1) {
        PUSHMARK(SP);
        XPUSHs(obj);
        PUTBACK;
        count = call_method("getline", G_SCALAR);
        if (count != 1) croak("Big trouble\n");
        SPAGAIN;
        buf_sv = POPs;
        if (SvOK(buf_sv)) {
            buf = SvPV(buf_sv, len);
            clen += len;
            ap_rwrite(buf, len, r);
        } else {
            break;
        }
    }
    if (len > 0) {
        ap_set_content_length(r, len);
    }
    PUSHMARK(SP);
    XPUSHs(obj);
    PUTBACK;
    call_method("close", G_DISCARD);
    SPAGAIN;
    PUTBACK;
    FREETMPS;
    LEAVE;
    return OK;
}

static int output_body(request_rec *r, SV *body)
{
    dTHX;
    int rc, type;
    switch (type = SvTYPE(SvRV(body))) {
        case SVt_PVAV:
            rc = output_body_ary(r, (AV *) SvRV(body));
            break;
        case SVt_PVGV:
            require_pv("IO/Handle.pm");
        case SVt_PVMG:
            rc = output_body_obj(r, body, type);
            break;
        default:
            server_error(r, "response body must be an array reference or object");
            rc = HTTP_INTERNAL_SERVER_ERROR;
            break;
    }
    return rc;
}

static int output_response(request_rec *r, SV *res)
{
    dTHX;
    AV *res_av;
    SV **status;
    SV **headers;
    AV *headers_av;
    SV **body;
    int rc;

    if (!SvROK(res) || SvTYPE(SvRV(res)) != SVt_PVAV) {
        server_error(r, "response must be an array reference");
        return HTTP_INTERNAL_SERVER_ERROR;
    }
    res_av = (AV *) SvRV(res);
    if (av_len(res_av) != 2) {
        server_error(r, "response must have 3 elements");
        return HTTP_INTERNAL_SERVER_ERROR;
    }

    status = av_fetch(res_av, 0, 0);
    if (!SvOK(*status)) {
        server_error(r, "response status must be a scalar value");
        return HTTP_INTERNAL_SERVER_ERROR;
    }
    rc = output_status(r, *status);
    if (rc != OK) return rc;

    headers = av_fetch(res_av, 1, 0);
    if (!SvROK(*headers) || SvTYPE(SvRV(*headers)) != SVt_PVAV) {
        server_error(r, "response headers must be an array reference");
        return HTTP_INTERNAL_SERVER_ERROR;
    }
    headers_av = (AV *) SvRV(*headers);
    if ((av_len(headers_av) + 1) % 2 != 0) {
        server_error(r, "num of response headers must be even");
        return HTTP_INTERNAL_SERVER_ERROR;
    }
    rc = output_headers(r, headers_av);
    if (rc != OK) return rc;

    body = av_fetch(res_av, 2, 0);
    if (!SvROK(*body)) {
        server_error(r, "response body must be a reference");
        return HTTP_INTERNAL_SERVER_ERROR;
    }
    rc = output_body(r, *body);

    return rc;
}

static void init_perl_variables()
{
    dTHX;
    GV *exit_gv = gv_fetchpv("CORE::GLOBAL::exit", TRUE, SVt_PVCV);
    GvCV(exit_gv) = get_cv("ModPSGI::exit", TRUE);
    GvIMPORTED_CV_on(exit_gv);
    hv_store(GvHV(PL_envgv), "MOD_PSGI", 8, newSVpv(MOD_PSGI_VERSION, 0), 0);
}

static SV *load_psgi(apr_pool_t *pool, const char *file)
{
    dTHX;
    SV *app;
    char *code;

    code = apr_psprintf(pool, "do q\"%s\" or die $@",
            ap_escape_quotes(pool, file));
    app = eval_pv(code, FALSE);

    if (SvTRUE(ERRSV)) {
        ap_log_error(APLOG_MARK, APLOG_NOERRNO|APLOG_ERR, 0, NULL, "%s", SvPV_nolen(ERRSV));
        return NULL;
    }
    if (!SvOK(app) || !SvROK(app) || SvTYPE(SvRV(app)) != SVt_PVCV) {
        ap_log_error(APLOG_MARK, APLOG_NOERRNO|APLOG_ERR, 0, NULL,
                "%s does not return an application code reference", file);
        return NULL;
    }
    return app;
}

static int psgi_handler(request_rec *r)
{
    SV *app, *env, *res;
    psgi_dir_config *c;

    if (strcmp(r->handler, PSGI_HANDLER_NAME)) {
        return DECLINED;
    }
    c = (psgi_dir_config *) ap_get_module_config(r->per_dir_config, &psgi_module);
    if (c->file == NULL) {
        ap_log_error(APLOG_MARK, APLOG_NOERRNO|APLOG_NOTICE, 0, r->server,
                "PSGIApp not configured");
        return DECLINED;
    }

    PERL_SET_CONTEXT(perlinterp);
    app = apr_hash_get(app_mapping, c->file, APR_HASH_KEY_STRING);
    if (app == NULL) {
        app = load_psgi(r->pool, c->file);
        if (app == NULL) {
            server_error(r, "%s had compilation errors.", c->file);
            return HTTP_INTERNAL_SERVER_ERROR;
        }
        apr_hash_set(app_mapping, c->file, APR_HASH_KEY_STRING, app);
    }
    env = make_env(r, c);
    res = run_app(r, app, env);
    if (res == NULL) {
        server_error(r, "invalid response");
        return HTTP_INTERNAL_SERVER_ERROR;
    }
    return output_response(r, res);
}

static apr_status_t psgi_child_exit(void *p)
{
    if (perlinterp == NULL) {
        PERL_SET_CONTEXT(perlinterp);
        PL_perl_destruct_level = 1;
        perl_destruct(perlinterp);
        perl_free(perlinterp);
        PERL_SYS_TERM();
        perlinterp = NULL;
    }
    return OK;
}

static void psgi_child_init(apr_pool_t *p, server_rec *s)
{
    apr_pool_cleanup_register(p, NULL, psgi_child_exit, psgi_child_exit);
}

static apr_status_t
psgi_pre_config(apr_pool_t *pconf, apr_pool_t *plog, apr_pool_t *ptemp)
{
    int argc = 2;
    char *argv[] = { "perl", "-e;0", NULL };
    char **envp = NULL;

    PERL_SYS_INIT3(&argc, (char ***) argv, &envp);
    perlinterp = perl_alloc();
    PL_perl_destruct_level = 1;
    perl_construct(perlinterp);
    perl_parse(perlinterp, xs_init, argc, argv, envp);
    PL_exit_flags |= PERL_EXIT_DESTRUCT_END;
    perl_run(perlinterp);
    init_perl_variables();

    psgi_apps = apr_array_make(pconf, 10, sizeof(char *));
    app_mapping = apr_hash_make(pconf);

    return OK;
}

static int
psgi_post_config(apr_pool_t *pconf, apr_pool_t *plog, apr_pool_t *ptemp, server_rec *s)
{
    dTHX;
    int i;
    char *file, **elts;
    SV *app;
    void *data;
    const char *userdata_key = "psgi_post_config";

    apr_pool_userdata_get(&data, userdata_key, s->process->pool);
    if (data == NULL) {
        apr_pool_userdata_set((const void *)1, userdata_key,
                apr_pool_cleanup_null, s->process->pool);
        return OK;
    }
    elts = (char **) psgi_apps->elts;
    for (i = 0; i < psgi_apps->nelts; i++) {
        file = elts[i];
        app = load_psgi(pconf, file);
        if (app == NULL) {
            ap_log_error(APLOG_MARK, APLOG_NOERRNO|APLOG_ERR, 0, NULL,
                    "%s had compilation errors.", file);
            return DONE;
        }
        apr_hash_set(app_mapping, file, APR_HASH_KEY_STRING, app);
    }

    ap_add_version_component(pconf, apr_psprintf(pconf, "mod_psgi/%s", MOD_PSGI_VERSION));

    return OK;
}

static void psgi_register_hooks(apr_pool_t *p)
{
    ap_hook_pre_config(psgi_pre_config, NULL, NULL, APR_HOOK_MIDDLE);
    ap_hook_post_config(psgi_post_config, NULL, NULL, APR_HOOK_MIDDLE);
    ap_hook_child_init(psgi_child_init, NULL, NULL, APR_HOOK_MIDDLE);
    ap_hook_handler(psgi_handler, NULL, NULL, APR_HOOK_MIDDLE);
}

static void *create_dir_config(apr_pool_t *p, char *path)
{
    psgi_dir_config *c = apr_pcalloc(p, sizeof(psgi_dir_config));
    c->file = NULL;
    c->location = path;
    return (void *) c;
}

static const char *cmd_psgi_app(cmd_parms *cmd, void *conf, const char *v)
{
    psgi_dir_config *c = (psgi_dir_config *) conf;
    c->file = (char *) apr_pstrdup(cmd->pool, v);
    *(const char **) apr_array_push(psgi_apps) = c->file;
    return NULL;
}

static const command_rec command_table[] = {
    AP_INIT_TAKE1("PSGIApp", cmd_psgi_app, NULL,
            OR_LIMIT, "set PSGI application"),
    { NULL }
};

module AP_MODULE_DECLARE_DATA psgi_module = {
    STANDARD20_MODULE_STUFF,
    create_dir_config,     /* create per-dir    config structures */
    NULL,                  /* merge  per-dir    config structures */
    NULL,                  /* create per-server config structures */
    NULL,                  /* merge  per-server config structures */
    command_table,         /* table of config file commands       */
    psgi_register_hooks    /* register hooks                      */
};

