use strict;
use warnings;
use t::TestModPSGI;

BEGIN {
    no warnings 'once';
    $YAML::LoadCode = 1;
}

{
    package t::ModPSGIHandle;
    sub new { bless \my $i, $_[0] }
    sub getline {
        my $self = shift;
        return $$self if $$self++ < 3;
        return;
    }
    sub close {
        my $self = shift;
#        warn "close called\nself: $$self";
    }
}

{
    package t::ModPSGIPath;
    sub new { bless \my $s, $_[0] }
    sub path { __FILE__ }
    # no getline
}

return eval_response_app if running_in_mod_psgi;

run_server_tests;

__END__

=== simple
--- request
method: GET
code: |
  [ 200, [ 'Content-Type' => 'text/plain' ], ['test'] ]
--- response
is_success: 1
content: test
code: 200
content_type: text/plain

=== status
--- request
method: GET
code: |
  [ 404, [ 'Content-Type' => 'text/plain' ], [ 'Not Found' ] ]
--- response
is_success: not ok
code: 404
content: Not Found

=== headers
--- request
method: GET
code: |
  [ 200, [ 'Content-Type' => 'text/plain', 'X-ModPSGI' => 1 ], [ '' ] ]
--- response
is_success: ok
content_type: text/plain
header:
  X-ModPSGI: 1

=== auto set content_length
--- request
method: GET
code: |
  [ 200, [ 'Content-Type' => 'text/plain' ], ['test'] ]
--- response
is_success: ok
content: test
code: 200
content_length: 4

=== multiple body
--- request
method: GET
code: |
  [ 200, [ 'Content-Type' => 'text/plain' ], ['foo', 'bar'] ]
--- response
is_success: ok
content: foobar

=== body filehandle
--- request
method: GET
code: !perl/code |
  {
    require Path::Class;
    my $file = Path::Class::file($0)->absolute;
    qq{
      open my \$fh, '<', "$file" or die \$!;
      [ 200, [ 'Content-Type' => 'text/plain' ], \$fh ];
    };
  }
--- response
is_success: ok
content_length: !perl/code |
  {
    require Path::Class;
    my $file = Path::Class::file($0);
    $file->stat->size;
  }
content: !perl/code |
  {
    require Path::Class;
    my $file = Path::Class::file($0);
    scalar $file->slurp;
  }

=== body filehandle like object
--- request
method: GET
code: |
  [ 200, [ 'Content-Type' => 'text/plain' ], t::ModPSGIHandle->new ]
--- response
is_success: ok
content: 123

=== body has path
--- request
method: GET
code: |
  [ 200, [ 'Content-Type' => 'text/plain' ], t::ModPSGIPath->new ]
--- response
is_success: ok
content: !perl/code |
  {
    require Path::Class;
    my $file = Path::Class::file($0);
    scalar $file->slurp;
  }

