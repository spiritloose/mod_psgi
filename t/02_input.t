use strict;
use warnings;
use lib '.';
use t::TestModPSGI;

return eval_body_app if running_in_mod_psgi;

run_server_tests;

__END__

=== isa
--- request
method: GET
code: |
  $env->{'psgi.input'}->isa('ModPSGI::Input');
--- response
is_success: ok
content: ok

=== can read
--- request
method: GET
code: |
  $env->{'psgi.input'}->can('read');
--- response
is_success: ok
content: ok

=== read
--- request
method: POST
code: |
  $env->{'psgi.input'}->read(my $buf, 1);
  $buf;
args:
  - foo: bar
--- response
is_success: ok
content: f

=== read all
--- request
method: POST
code: |
  $env->{'psgi.input'}->read(my $buf, $env->{CONTENT_LENGTH});
  join('&', sort split('&', $buf))
args:
  - a: 1
    b: 2
--- response
is_success: ok
content: a=1&b=2

=== read each bytes
--- request
method: POST
code: |
  my ($buf, $read);
  while ($env->{'psgi.input'}->read($read, 1)) {
      $buf .= $read;
  }
  $buf;
args:
  - foo: bar
--- response
is_success: ok
content: foo=bar

=== read offset 0
--- request
method: POST
code: |
  $env->{'psgi.input'}->read(my $buf, 1, 0);
  $buf;
args:
  - foo: bar
--- response
is_success: ok
content: f

=== read offset 1
--- request
method: POST
code: |
  $env->{'psgi.input'}->read(my $buf, 1, 1);
  $buf;
args:
  - foo: bar
--- response
is_success: not ok

