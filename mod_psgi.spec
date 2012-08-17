%{!?_httpd_apxs: %{expand: %%global _httpd_apxs %%{_sbindir}/apxs}}
%{!?_httpd_mmn: %{expand: %%global _httpd_mmn %%(cat %{_includedir}/httpd/.mmn || echo missing-httpd-devel)}}
%{!?_httpd_confdir:    %{expand: %%global _httpd_confdir    %%{_sysconfdir}/httpd/conf.d}}
# /etc/httpd/conf.d with httpd < 2.4 and defined as /etc/httpd/conf.modules.d with httpd >= 2.4
%{!?_httpd_modconfdir: %{expand: %%global _httpd_modconfdir %%{_sysconfdir}/httpd/conf.d}}

Name:           mod_psgi
Version:        0.0.1
Release:        1%{?dist}
Summary:        A PSGI interface for Plack/Perl web applications in Apache

Group:          System Environment/Libraries
License:        ASL 2.0
URL:            http://github.com/spiritloose/mod_psgi
Source0:        https://github.com/spiritloose/mod_psgi/downloads/%{name}-%{version}.tar.gz
Source1:        psgi.conf
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

BuildRequires:  autoconf
BuildRequires:  httpd-devel
BuildRequires:  perl-devel
Requires: httpd-mmn = %{_httpd_mmn}

%description
The mod_psgi adapter is an Apache module that provides a PSGI compliant
interface for hosting Perl based web applications within Apache. The
adapter is written completely in C code against the Apache C runtime and
for hosting PSGI applications within Apache has a lower overhead than using
existing PSGI adapters for mod_perl or CGI.


%prep
%setup -q

%build
autoconf
%configure --enable-shared --with-apxs=%{_httpd_apxs}
make LDFLAGS="-L%{_libdir}" %{?_smp_mflags}


%install
rm -rf $RPM_BUILD_ROOT
make install DESTDIR=$RPM_BUILD_ROOT

install -d -m 755 $RPM_BUILD_ROOT%{_httpd_modconfdir}
%if "%{_httpd_modconfdir}" == "%{_httpd_confdir}"
# httpd <= 2.2.x
install -p -m 644 %{SOURCE1} $RPM_BUILD_ROOT%{_httpd_confdir}/psgi.conf
%else
# httpd >= 2.4.x
install -p -m 644 %{SOURCE1} $RPM_BUILD_ROOT%{_httpd_modconfdir}/10-psgi.conf
%endif

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%doc LICENCE README
%config(noreplace) %{_httpd_modconfdir}/*.conf
%{_libdir}/httpd/modules/mod_psgi.so


%changelog
* Fri Aug 18 2012 Dean Hamstead <dean.hamstead@optusnet.com.au>
- Botch together the .spec file from the mod_wsgi spec file in fc18
