package MetaCPAN::Role::Script;

use Moose::Role;

use ElasticSearchX::Model::Document::Types qw(:all);
use FindBin;
use Git::Helpers qw( checkout_root );
use Log::Contextual qw( :log :dlog );
use MetaCPAN::Model;
use MetaCPAN::Types qw(:all);
use MetaCPAN::Queue ();

use Carp ();

with 'MetaCPAN::Role::HasConfig';
with 'MetaCPAN::Role::Fastly';
with 'MetaCPAN::Role::Logger';

has cpan => (
    is      => 'ro',
    isa     => Dir,
    lazy    => 1,
    builder => '_build_cpan',
    coerce  => 1,
    documentation =>
        'Location of a local CPAN mirror, looks for $ENV{MINICPAN} and ~/CPAN',
);

has die_on_error => (
    is            => 'ro',
    isa           => Bool,
    default       => 0,
    documentation => 'Die on errors instead of simply logging',
);

has ua => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_ua',
);

has proxy => (
    is      => 'ro',
    isa     => Str,
    default => '',
);

has es => (
    is            => 'ro',
    isa           => ES,
    required      => 1,
    coerce        => 1,
    documentation => 'Elasticsearch http connection string',
);

has model => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_model',
    traits  => ['NoGetopt'],
);

has index => (
    reader        => '_index',
    is            => 'ro',
    isa           => Str,
    default       => 'cpan',
    documentation => 'Index to use, defaults to "cpan"',
);

has port => (
    isa           => Int,
    is            => 'ro',
    required      => 1,
    documentation => 'Port for the proxy, defaults to 5000',
);

has home => (
    is      => 'ro',
    isa     => Dir,
    lazy    => 1,
    coerce  => 1,
    default => sub { checkout_root() },
);

has _minion => (
    is      => 'ro',
    isa     => 'Minion',
    lazy    => 1,
    handles => { _add_to_queue => 'enqueue', stats => 'stats', },
    default => sub { MetaCPAN::Queue->new->minion },
);

has queue => (
    is            => 'ro',
    isa           => Bool,
    default       => 0,
    documentation => 'add indexing jobs to the minion queue',
);

sub handle_error {
    my ( $self, $error ) = @_;

    # Always log.
    log_fatal {$error};

    # Die if configured (for the test suite).
    Carp::croak $error if $self->die_on_error;
}

sub index {
    my $self = shift;
    return $self->model->index( $self->_index );
}

sub _build_model {
    my $self = shift;

    # es provided by ElasticSearchX::Model::Role
    return MetaCPAN::Model->new( es => $self->es );
}

sub _build_ua {
    my $self  = shift;
    my $ua    = LWP::UserAgent->new;
    my $proxy = $self->proxy;

    if ($proxy) {
        $proxy eq 'env'
            ? $ua->env_proxy
            : $ua->proxy( [qw<http https>], $proxy );
    }

    return $ua;
}

sub _build_cpan {
    my $self = shift;
    my @dirs = (
        $ENV{MINICPAN},    '/home/metacpan/CPAN',
        "$ENV{HOME}/CPAN", "$ENV{HOME}/minicpan",
    );
    foreach my $dir ( grep {defined} @dirs ) {
        return $dir if -d $dir;
    }
    die
        "Couldn't find a local cpan mirror. Please specify --cpan or set MINICPAN";

}

sub remote {
    shift->es->nodes->info->[0];
}

sub run { }
before run => sub {
    my $self = shift;

    $self->set_logger_once;

    #Dlog_debug {"Connected to $_"} $self->remote;
};

1;

__END__

=pod

=head1 SYNOPSIS

Roles which should be available to all modules

=cut
