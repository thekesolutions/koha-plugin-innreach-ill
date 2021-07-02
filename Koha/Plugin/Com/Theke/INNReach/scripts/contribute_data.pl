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
my $force         = 0;
my $overwrite_locations = 0;
my $decontribute;
my $delete_location;
my $update_location;
my $central_server;
my $help;

my $result = GetOptions(
    'biblio_id=s'         => \$biblio_id,
    'all_biblios'         => \$all_biblios,
    'exclude_items'       => \$exclude_items,
    'force'               => \$force,
    'overwrite_locations' => \$overwrite_locations,
    'decontribute'        => \$decontribute,
    'delete_location=s'   => \$delete_location,
    'update_location=s'   => \$update_location,
    'noout'               => \$noout,
    'central_server=s'    => \$central_server,
    'help'                => \$help,
);

unless ($result) {
    print_usage();
    say "Not sure what wen't wrong";
    exit 1;
}

if ( $help ) {
    print_usage();
    exit 0;
}

unless ( $central_server ) {
    print_usage();
    say "--central_server is missing (mandatory)";
    exit 1;
}

if ( $biblio_id and $all_biblios ) {
    print_usage();
    say "--biblio_id and --all are mutually exclussive";
    exit 1;
}

sub print_usage {
    print <<_USAGE_;

Options:

    --central_server       Contribute to the specified central server (mandatory)
    --noout                No output
    --force                Force action (check the code for cases)

Record contribution actions:

    --biblio_id  id        Only contribute the specified biblio_id
    --all_biblios          Contribute all records
    --exclude_items        Exclude items from this batch update

    --decontribute         Tells the tool the action is to decontribute

Locations actions:

    --overwrite_locations  Update Central server's locations
    --delete_location id   Sends a request to remove library id from the locations list
    --update_location id   Sends a request to update library id from the locations list

Note: --biblio_id and --all_biblios are mutually exclussive

_USAGE_
}

my $contribution = Koha::Plugin::Com::Theke::INNReach::Contribution->new;

unless ( any { $_ eq $central_server } @{$contribution->{centralServers}} ) { # valid?
    print_usage();
    say "$central_server is not a valid configured central server!";
    exit 1;
}

if ( $biblio_id or $all_biblios ) {
    my $query = {};
    if ($biblio_id) {
        $query = { biblionumber => $biblio_id };
    }

    my $biblios = Koha::Biblios->search($query);
    if ( $decontribute ) {
        while ( my $biblio = $biblios->next ) {
            print STDOUT "# Decontributing record: " . $biblio->id . "\n"
                unless $noout;
            my @errors = $contribution->decontribute_bib(
                {
                    bibId         => $biblio->biblionumber,
                    centralServer => $central_server
                }
            );
            if ( @errors ) {
                print STDOUT " - Status: Error (" . join( ' - ', @errors ) . ")\n"
                    unless $noout;
            }
            else {
                print STDOUT " - Status: OK\n"
                    unless $noout;
            }
        }
    }
    else {
        while ( my $biblio = $biblios->next ) {

            my $items = $contribution->filter_items_by_contributable(
                {
                    central_server => $central_server,
                    items          => $biblio->items
                }
            );

            if ( $items->count > 0 or $force ) {
                print STDOUT "# Contributing record: " . $biblio->id . "\n"
                    unless $noout;
                my @errors = $contribution->contribute_bib(
                    {
                        bibId         => $biblio->biblionumber,
                        centralServer => $central_server
                    }
                );
                if ( @errors ) {
                    print STDOUT " - Status: Error (" . join( ' - ', @errors ) . ")\n"
                        unless $noout;
                }
                else {
                    print STDOUT " - Status: OK\n"
                        unless $noout;
                }
            }
            else {
                print STDOUT " - Status: Skipped (no items)\n"
                    unless $noout;
            }

            unless ( $exclude_items ) {
                if ( $items->count > 0 ) {
                    print STDOUT " - Items:\n"
                        unless $noout;
                    while ( my $item = $items->next ) {
                        my @errors = $contribution->contribute_batch_items(
                            {
                                bibId         => $biblio->biblionumber,
                                centralServer => $central_server,
                                item          => $item,
                            }
                        );
                        if ( @errors ) {
                            print STDOUT "        > " . $item->id . ": Error (" . join( ' - ', @errors ) . ")\n"
                                unless $noout;
                        }
                        else {
                            print STDOUT "        > " . $item->id . ": Ok\n"
                                unless $noout;
                        }
                    }
                }
                else {
                    print STDOUT " - Items: biblio has no items\n"
                        unless $noout;
                }
            }
        }
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

if ( $update_location ) {
    $contribution->update_single_location(
        {
            library_id    => $update_location,
            centralServer => $central_server
        }
    );
}

1;
