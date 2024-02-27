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
use Koha::Script;
use List::MoreUtils qw(any);
use Try::Tiny;

use Koha::Plugin::Com::Theke::INNReach;

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $biblio_id;
my $biblios       = 0;
my $items         = 0;
my $where;
my $noout         = 0;
my $exclude_items = 0;
my $force         = 0;
my $overwrite_locations = 0;
my $decontribute;
my $delete_location;
my $update_location;
my $central_server;
my $recontribution;
my $only_items;
my $all;
my $help;

my $result = GetOptions(
    'biblio_id=s'         => \$biblio_id,
    'biblios'             => \$biblios,
    'items'               => \$items,
    'where=s'             => \$where,
    'exclude_items'       => \$exclude_items,
    'force'               => \$force,
    'overwrite_locations' => \$overwrite_locations,
    'decontribute'        => \$decontribute,
    'delete_location=s'   => \$delete_location,
    'update_location=s'   => \$update_location,
    'noout'               => \$noout,
    'central_server=s'    => \$central_server,
    'recontribution'      => \$recontribution,
    'only_items'          => \$only_items,
    'all'                 => \$all,
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

if ( $biblio_id and $where ) {
    print_usage();
    say "--biblio_id and --where are mutually exclussive";
    exit 1;
}

if ( $biblios and $items ) {
    prunt_usage();
    say "--biblios and --items are mutually exclussive";
    exit 1;
}

sub print_usage {
    print <<_USAGE_;

Options:

    --central_server       Contribute to the specified central server (mandatory)
    --noout                No output
    --force                Force action (check the code for cases)
    --recontribution       Work in recontribution mode

Record/item contribution actions:

    --biblios              Triggers biblio (de)contribution
    --items                Triggers item (de)contribution
    --biblio_id  id        Only contribute the specified biblio_id
    --where                SQL WHERE conditions on biblios
    --exclude_items        Exclude items from this batch update

    --decontribute         Tells the tool the action is to decontribute

Recontribution option:

    --all                  Recontribute everything
    --only-items           Only recontribute items
    --only-biblios         Only recontribute biblios (NOT IMPLEMENTED)

Locations actions:

    --overwrite_locations  Update Central server's locations
    --delete_location id   Sends a request to remove library id from the locations list
    --update_location id   Sends a request to update library id from the locations list

Note: --biblio_id, --items and --all_biblios are mutually exclussive

_USAGE_
}

my $plugin = Koha::Plugin::Com::Theke::INNReach->new;

unless ( any { $_ eq $central_server } @{$plugin->central_servers} ) { # valid?
    print_usage();
    say "$central_server is not a valid configured central server!";
    exit 1;
}

my $contribution = $plugin->contribution($central_server);

if ($items) {

    unless ($decontribute) {
        print_usage();
        say "For --items, only decontribution is implemented";
        exit 1;
    }

    unless ($where) {
        print_usage();
        say "--where is mandatory for --items";
        exit 1;
    }

    # normal flow
    my $configuration = $plugin->configuration->{$central_server};
    my $exclude_empty_biblios =
        $configuration->{contribution} ? $configuration->{contribution}->{exclude_empty_biblios} : 0;

    my $query    = \[$where];
    my $items_rs = Koha::Items->search($query);

    while ( my $item = $items_rs->next ) {
        my $biblio              = $item->biblio;
        my $contributable_items = $contribution->filter_items_by_contributable(
            {
                central_server => $central_server,
                items          => $biblio->items
            }
        );

        if ( $contributable_items->count == 0 && $exclude_empty_biblios ) {
            print STDOUT "# Decontributing empty biblio: " . $biblio->id . "\n";
            my $errors = $contribution->decontribute_bib(
                {
                    bibId         => $biblio->id,
                    centralServer => $central_server,
                }
            );
            if ( $errors->{$central_server} ) {
                print STDOUT " - Status: Error (" . $errors->{$central_server} . ")\n"
                    unless $noout;
            } else {
                print STDOUT " - Status: OK\n"
                    unless $noout;
            }

        } else {
            print STDOUT "# Decontributing item: " . $item->id . "\n";
            my $errors = $contribution->decontribute_item(
                {
                    itemId        => $item->id,
                    centralServer => $central_server,
                }
            );
            if ( $errors->{$central_server} ) {
                print STDOUT " - Status: Error (" . $errors->{$central_server} . ")\n"
                    unless $noout;
            } else {
                print STDOUT " - Status: OK\n"
                    unless $noout;
            }
        }
    }
}

if ( $biblio_id or $biblios ) {
    my $query = {};
    if ($biblio_id) {
        $query = { biblionumber => $biblio_id };
    }
    elsif ($where) {
        $query = \[ $where ];
    }

    my $biblios = Koha::Biblios->search($query);
    if ( $decontribute ) {
        while ( my $biblio = $biblios->next ) {
            print STDOUT "# Decontributing record: " . $biblio->id . "\n"
                unless $noout;
            my $errors = $contribution->decontribute_bib(
                {
                    bibId         => $biblio->biblionumber,
                    centralServer => $central_server
                }
            );
            if ( $errors->{$central_server} ) {
                print STDOUT " - Status: Error (" . $errors->{$central_server} . ")\n"
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

            print STDOUT "# Contributing record: " . $biblio->id . "\n"
                unless $noout;

            if ( $items->count > 0 or $force ) {
                my $errors = $contribution->contribute_bib(
                    {
                        bibId         => $biblio->biblionumber,
                        centralServer => $central_server
                    }
                );

                if ( $errors->{$central_server} ) {
                    print STDOUT " - Status: Error (" . $errors->{$central_server} . ")\n"
                        unless $noout;
                    next;
                }
                else {
                    print STDOUT " - Status: OK\n"
                        unless $noout;
                }
            }
            else {
                print STDOUT " - Status: Skipped (no items)\n"
                    unless $noout;
                next;
            }

            unless ( $exclude_items ) {
                if ( $items->count > 0 ) {
                    print STDOUT " - Items:\n"
                        unless $noout;
                    while ( my $item = $items->next ) {
                        my $errors = {};
                        try {
                            my $errors = $contribution->contribute_batch_items(
                                {
                                    bibId         => $biblio->biblionumber,
                                    centralServer => $central_server,
                                    item          => $item,
                                }
                            );
                        }
                        catch {
                            $errors->{$central_server} = "$_";
                        };
                        if ( $errors->{$central_server} ) {
                            print STDOUT "        > " . $item->id . ": Error (" . $errors->{$central_server} . ")\n"
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

if ( $recontribution ) {
    if ( $all or $only_items ) {
        # remove items to be de-contributed
        my $deleted_contributed_items = $contribution->get_deleted_contributed_items(
            {
                central_server => $central_server,
            }
        );

        if ( scalar @{$deleted_contributed_items} > 0 )  {
            print STDOUT "# Decontributing (deleted) items:\n"
                unless $noout;

            foreach my $item_id ( @{$deleted_contributed_items} ) {
                my $errors = $contribution->decontribute_item(
                    {
                        centralServer => $central_server,
                        itemId        => $item_id,
                    }
                );
                if ( $errors->{$central_server} ) {
                    print STDOUT "\t$item_id\t> Error (" . $errors->{$central_server} . ")\n"
                        unless $noout;
                }
                else {
                    print STDOUT "\t$item_id\t> Ok\n"
                        unless $noout;
                }
            }
        }

        my $items_to_be_decontributed = $contribution->filter_items_by_to_be_decontributed(
            {
                central_server => $central_server,
                items          => Koha::Items->new,
            }
        );

        if ( $items_to_be_decontributed->count > 0 ) {
            print STDOUT "# Decontributing items (rules):\n"
                unless $noout;

            while( my $item = $items_to_be_decontributed->next ) {
                my $errors = $contribution->decontribute_item(
                    {
                        centralServer => $central_server,
                        itemId        => $item->id,
                    }
                );
                if ( $errors->{$central_server} ) {
                    print STDOUT "\t" . $item->id . "\t> Error (" . $errors->{$central_server} . ")\n"
                        unless $noout;
                }
                else {
                    print STDOUT "\t" . $item->id . "\t> Ok\n"
                        unless $noout;
                }
            }
        }

        my $items_to_recontribute = $contribution->filter_items_by_contributed(
            {
                central_server => $central_server,
                items          => Koha::Items->new,
            }
        );

        if ( $items_to_recontribute->count > 0 ) {
            print STDOUT "# Recontributing items:\n"
                unless $noout;

            while( my $item = $items_to_recontribute->next ) {
                my $errors = $contribution->contribute_batch_items(
                    {
                        centralServer => $central_server,
                        bibId         => $item->biblionumber,
                        item          => $item,
                    }
                );
                if ( $errors->{$central_server} ) {
                    print STDOUT "\t" . $item->id . "\t> Error (" . $errors->{$central_server} . ")\n"
                        unless $noout;
                }
                else {
                    print STDOUT "\t" . $item->id . "\t> Ok\n"
                        unless $noout;
                }
            }
        }
    }
}

1;
