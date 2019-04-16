#/usr/bin/perl

use Modern::Perl;

use Data::Printer colored => 1;

use Getopt::Long;

use Koha::Plugin::Com::Theke::INNReach::Contribution;

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $biblio_id;
my $all           = 0;
my $noout         = 0;
my $exclude_items = 0;

my $result = GetOptions(
    'biblio_id=s'   => \$biblio_id,
    'all'           => \$all,
    'exclude_items' => \$exclude_items,
    'noout'         => \$noout,
);

unless ($result) {
    print_usage();
    die "Not sure what wen't wrong";
}

if ( $biblio_id and $all ) {
    print_usage();
    die "biblio_id and all are mutually exclussive";
}

sub print_usage {
    print <<_USAGE_;

    C'mon! Valid options are

    --biblio_id     Only contribute the specified biblio_id
    --all           Contribute all records
    --exclude_items Exclude items from this batch update
    --noout         No generar output de registros

Note: --biblio_id and --all are mutually exclussive

_USAGE_
}

my $contribution = Koha::Plugin::Com::Theke::INNReach::Contribution->new;

if ($biblio_id) {
    $contribution->contribute_bib( { bibId => $biblio_id } );
    $contribution->contribute_batch_items( { bibId => $biblio_id } )
        unless $exclude_items;
}
elsif ($all) {

    # all of them!
    my $biblios = Koha::Biblios->search;
    while ( my $biblio = $biblios->next ) {
        $contribution->contribute_bib( { bibId => $biblio->biblionumber } );
        $contribution->contribute_batch_items( { bibId => $biblio->biblionumber } )
            unless $exclude_items;
    }
}

1;
