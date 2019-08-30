Name:		mod_psgi
Version:	0.0.1
Release:	2%{?dist}
Summary:	Perl PSGI modules for the Apache HTTP Server

Group:		System Environment/Daemons
License:	Apache License 2.0
URL:		https://github.com/spiritloose/mod_psgi
Source0:	https://github.com/spiritloose/mod_psgi/mod_psgi-0.0.1.tar.gz

BuildRequires:	httpd-devel >= 2.4
BuildRequires:	httpd-devel >= 2.4
Requires:	httpd >= 2.4

%description
The mod_psgi module adds support for Perl PSGI to the Apache HTTP Server.

%prep
%setup -q

%build
autoconf
%configure
make %{?_smp_mflags}

%install
make install DESTDIR=%{buildroot}
mkdir -p %{buildroot}/%{_sysconfdir}/httpd/conf.modules.d/
cp 01-psgi.conf %{buildroot}/%{_sysconfdir}/httpd/conf.modules.d/

%post
service httpd reload

%files
%defattr(-,root,root)
%{_libdir}/httpd/modules/mod_psgi.so
%config(noreplace) %{_sysconfdir}/httpd/conf.modules.d/01-psgi.conf

%changelog
