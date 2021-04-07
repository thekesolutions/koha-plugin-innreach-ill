#/usr/bin/perl

#
# Copyright 2019 Theke Solutions
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# This program comes with ABSOLUTELY NO WARRANTY;

use Modern::Perl;

use Data::Printer colored => 1;

use Getopt::Long;
use List::MoreUtils qw(any);

use Koha::Plugin::Com::Theke::INNReach::Contribution;

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $biblio_id;
my $all_biblios   = 0;
my $noout         = 0;
my $exclude_items = 0;
my $overwrite_locations = 0;
my $delete_location;
my $central_server;

my $result = GetOptions(
    'biblio_id=s'         => \$biblio_id,
    'all_biblios'         => \$all_biblios,
    'exclude_items'       => \$exclude_items,
    'overwrite_locations' => \$overwrite_locations,
    'delete_location=s'   => \$delete_location,
    'noout'               => \$noout,
    'central_server=s'    => \$central_server,
);

unless ($result) {
    print_usage();
    die "Not sure what wen't wrong";
}

unless ( $central_server ) {
    print_usage();
    die "--central_server is missing (mandatory)";
}

if ( $biblio_id and $all_biblios ) {
    print_usage();
    die "--biblio_id and --all are mutually exclussive";
}

sub print_usage {
    print <<_USAGE_;

    C'mon! Valid options are

    --central_server       Only contribute to the specified central server

    --biblio_id            Only contribute the specified biblio_id
    --all_biblios          Contribute all records
    --exclude_items        Exclude items from this batch update
    --overwrite_locations  Update Central server's locations
    --delete_location id   Sends a request to remove library id from the locations list
    --noout                No output

Note: --biblio_id and --all are mutually exclussive

_USAGE_
}

my $contribution = Koha::Plugin::Com::Theke::INNReach::Contribution->new;

unless ( any { $_ eq $central_server } @{$contribution->{centralServers}} ) { # valid?
    print_usage();
    die "$central_server is not a valid configured central server!";
}

if ( $biblio_id or $all_biblios ) {
    my $query = {};
    if ($biblio_id) {
        $query = { biblionumber => $biblio_id };
    }

    my $biblios = Koha::Biblios->search($query);
    while ( my $biblio = $biblios->next ) {
        $contribution->contribute_bib(
            {
                bibId         => $biblio->biblionumber,
                centralServer => $central_server
            }
        );
        $contribution->contribute_batch_items(
            {
                bibId         => $biblio->biblionumber,
                centralServer => $central_server
            }
        ) unless $exclude_items;
    }
}

if ( $overwrite_locations ) {
    my $response = $contribution->get_locations_list( { centralServer => $central_server } );

    # delete current locations
    foreach my $location ( @{ $response } ) {
        $contribution->delete_single_location(
            {
                library_id    => $location->{locationKey},
                centralServer => $central_server
            }
        );
    }
    # upload all new locations
    $contribution->upload_locations_list({ centralServer => $central_server });
}

if ( $delete_location ) {
    $contribution->delete_single_location(
        {
            library_id    => $delete_location,
            centralServer => $central_server
        }
    );
}

1;
