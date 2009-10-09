use strict;
use warnings;
use Test::More;
use File::Temp;
use Plack::Test::Suite;

warn $ENV{HTTPD};
Plack::Test::Suite->run_server_tests(\&run_httpd);
done_testing();

sub run_httpd {
    my $port = shift;

    my $tmpdir = $ENV{APACHE2_TMP_DIR} || File::Temp::tempdir( CLEANUP => 1 );

    write_file("$tmpdir/app.psgi", _render_psgi());
    write_file("$tmpdir/httpd.conf", _render_conf($tmpdir, $port, "$tmpdir/app.psgi"));

    exec "httpd -X -D FOREGROUND -f $tmpdir/httpd.conf";
}

sub write_file {
    my($path, $content) = @_;

    open my $out, ">", $path or die "$path: $!";
    print $out $content;
}

sub _render_psgi {
    return <<'EOF';
use lib "lib";
use Plack::Test::Suite;

Plack::Test::Suite->test_app_handler;
EOF
}

sub _render_conf {
    my ($tmpdir, $port, $psgi_path) = @_;
    <<"END";
LoadModule psgi_module modules/mod_psgi.so
PidFile $tmpdir/httpd.pid
LockFile $tmpdir/httpd.lock
ErrorLog $tmpdir/error_log
Listen $port

<Location />
SetHandler psgi
PSGIApp $tmpdir/app.psgi
</Location>
END
}
