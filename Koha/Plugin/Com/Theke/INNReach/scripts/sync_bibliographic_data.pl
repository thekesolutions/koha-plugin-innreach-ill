#/usr/bin/perl

# Copyright 2021 Theke Solutions
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

use C4::Context;
use Koha::Biblios;

use Koha::Plugin::Com::Theke::INNReach;
use Koha::Plugin::Com::Theke::INNReach::Contribution;

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $biblio_id;
my $central_server;
my $exclude_items;
my $help;
my $limit;
my $noout;
my $where;

my $result = GetOptions(
    'biblio_id=s'      => \$biblio_id,
    'central_server=s' => \$central_server,
    'exclude_items'    => \$exclude_items,
    'help'             => \$help,
    'limit=i'          => \$limit,
    'noout'            => \$noout,
    'where=s'          => \$where,
);

unless ($result) {
    print_usage();
    say "Not sure what wen't wrong";
    exit 1;
}

if ($help) {
    print_usage();
    exit 0;
}

unless ($central_server) {
    print_usage();
    say "--central_server is missing (mandatory)";
    exit 1;
}

if ( $biblio_id and $where ) {
    print_usage();
    say "--biblio_id and --where are mutually exclussive";
    exit 1;
}

sub print_usage {
    print <<_USAGE_;

This script takes care of sinchronizing biblios and items with the specified central
server, based on the configuration. It can be run to acknowledge configuration changes
or even for an initial contribution.

If you want more fine-grained control (e.g. force contribution of records that wouldn't
be contributed because of the configuration) use contribute_data.pl

Options:

    --central_server       Contribute to the specified central server (mandatory)
    --where "condition"    Conditions on `biblio` table columns (_SQL_ `WHERE` syntax)
    --biblio_id "id"       A particular biblionumber specified.

    --noout                No output
    --help                 This help

_USAGE_
}

my $plugin       = Koha::Plugin::Com::Theke::INNReach->new;
my $contribution = Koha::Plugin::Com::Theke::INNReach::Contribution->new( { plugin => $plugin } );

my $query      = {};
my $attributes = {};

if ($biblio_id) {
    $query = { biblionumber => $biblio_id };
} elsif ($where) {    # where
    $query = \[$where];
}

$attributes = { rows => $limit }
    if $limit;

my $biblios = Koha::Biblios->search( $query, $attributes );

while ( my $biblio = $biblios->next ) {

    if ( $contribution->is_bib_contributed( { biblio_id => $biblio->id, central_server => $central_server } ) ) {
        my $contributable_items = $contribution->filter_items_by_contributable(
            { items => $biblio->items, central_server => $central_server } );

        if ( $contributable_items->count == 0 ) {
            $plugin->schedule_task(
                {
                    action         => 'delete',
                    central_server => $central_server,
                    object_id      => $biblio->id,
                    object_type    => 'biblio',
                    status         => 'queued',
                }
            );
            print STDOUT "Record: " . $biblio->id . "\tdecontribute\n"
                unless $noout;
        } else {
            print STDOUT "Record: " . $biblio->id . "\tkeep\n"
                unless $noout;

            my @to_decontribute_item_ids = $contribution->filter_items_by_to_be_decontributed(
                { central_server => $central_server, items => $biblio->items } )->get_column('itemnumber');
            my @contributed_item_ids = $contribution->filter_items_by_contributed(
                { central_server => $central_server, items => $biblio->items } )->get_column('itemnumber');
            my @to_contribute_item_ids =
                scalar @contributed_item_ids
                ? $contribution->filter_items_by_contributable(
                { central_server => $central_server, items => $biblio->items } )
                ->search( { itemnumber => { not_in => \@contributed_item_ids } } )->get_column('itemnumber')
                : $contribution->filter_items_by_contributable(
                { items => $biblio->items, central_server => $central_server } )->get_column('itemnumber');

            print STDOUT "\t> items\n"
                unless $noout and ( scalar @to_decontribute_item_ids > 0 || scalar @to_contribute_item_ids > 0 );
            foreach my $item_id (@to_decontribute_item_ids) {
                $plugin->schedule_task(
                    {
                        action         => 'delete',
                        central_server => $central_server,
                        object_id      => $item_id,
                        object_type    => 'item',
                        status         => 'queued',
                    }
                );
                print STDOUT "\t\t * $item_id (decontribute)\n" unless $noout;
            }

            foreach my $item_id (@to_contribute_item_ids) {
                $plugin->schedule_task(
                    {
                        action         => 'create',
                        central_server => $central_server,
                        object_id      => $item_id,
                        object_type    => 'item',
                        status         => 'queued',
                    }
                );
                print STDOUT "\t\t * $item_id (contribute)\n" unless $noout;
            }
        }
    } else {

        # Not yet contributed, check
        my $items = $contribution->filter_items_by_contributable(
            {
                central_server => $central_server,
                items          => $biblio->items
            }
        );

        if ( $items->count > 0 ) {

            print STDOUT $biblio->id . "\tcontribute\n"
                unless $noout;
            $plugin->schedule_task(
                {
                    action         => 'create',
                    central_server => $central_server,
                    object_id      => $biblio->id,
                    object_type    => 'biblio',
                    status         => 'queued',
                }
            );

            print STDOUT "\t> items\n"
                unless $noout;

            while ( my $item = $items->next ) {
                $plugin->schedule_task(
                    {
                        action         => 'create',
                        central_server => $central_server,
                        object_id      => $item->id,
                        object_type    => 'item',
                        status         => 'queued',
                    }
                );
                print STDOUT "\t\t * " . $item->id . " (contribute)\n" unless $noout;
            }
        }
    }
}

1;

