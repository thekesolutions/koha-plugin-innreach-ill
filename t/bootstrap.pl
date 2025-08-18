#!/usr/bin/perl

# This file is part of the INNReach plugin
#
# The INNReach plugin is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# The INNReach plugin is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with The INNReach plugin; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use DDP;
use File::Slurp;
use Try::Tiny qw(catch try);

use C4::Context;
use Koha::Database;
use Koha::ItemTypes;
use Koha::Patron::Categories;

# For generating random data
use t::lib::TestBuilder;

use Koha::Plugin::Com::Theke::INNReach;

my $builder = t::lib::TestBuilder->new;
my $plugin  = Koha::Plugin::Com::Theke::INNReach->new;

C4::Context->set_preference( 'ILLModule', 1 )
    && step("ILLModule set");

C4::Context->set_preference( 'RESTBasicAuth', 1 )
    && step("RESTBasicAuth set");

my $dbh = C4::Context->dbh;

# Make sure the plugin is enabled
$dbh->do(q{
    UPDATE plugin_data SET plugin_value=1
    WHERE plugin_key='__ENABLED__'
      AND plugin_class='Koha::Plugin::Com::Theke::INNReach'
}) && step("Enabled INNReach plugin");

$dbh->do(q{
    UPDATE plugin_data SET plugin_value=0
    WHERE plugin_key='__ENABLED__'
      AND plugin_class<>'Koha::Plugin::Com::Theke::INNReach'
}) && step("Disabled other plugins");

my $config_string = read_file('/kohadevbox/plugins/innreach/t/config.yaml');
$plugin->store_data(
    {
        configuration => $config_string,
    }
);
step("Configuration loaded (from t/config.yaml)");

if (
    $builder->build_object(
        {
            class => 'Koha::Libraries',
            value => { branchcode => 'ILL', pickup_location => 1 }
        }
    )
    )
{
    step("Added 'ILL' library");

} else {
    step("Add 'ILL' library [SKIPPED]");
}

# Create necessary patron categories
foreach my $category_data (
    { categorycode => 'ILL',      description => 'ILL Patrons' },
    { categorycode => 'ILLLIBS',  description => 'ILL Libraries' },
    { categorycode => 'LIBSTAFF', description => 'Library Staff' },
    { categorycode => 'AP',       description => 'Adult Patron' },
    { categorycode => 'CH',       description => 'Child Patron' },
    { categorycode => 'DR',       description => 'Doctor' },
    { categorycode => 'DR2',      description => 'Doctor 2' },
    { categorycode => 'NR',       description => 'Non-Resident' },
    { categorycode => 'SR',       description => 'Senior' },
) {
    if ( !Koha::Patron::Categories->search({ categorycode => $category_data->{categorycode} })->count) {
        Koha::Patron::Category->new({
            categorycode => $category_data->{categorycode},
            description => $category_data->{description},
            enrolmentperiod => 99,
            upperagelimit => 999,
            dateofbirthrequired => 0,
            enrolmentfee => 0.00,
            overduenoticerequired => 0,
            reservefee => 0.00,
            hidelostitems => 0,
            category_type => 'A'
        })->store();
        step( "Add $category_data->{categorycode} patron category" );
    } else {
        step( "Add $category_data->{categorycode} patron category [SKIPPED]" );
    }
}

foreach my $item_type ( qw(D2IR_BK D2IR_CF) ) {

    if ( !Koha::ItemTypes->search({ itemtype => $item_type })->count) {
        Koha::ItemType->new({ itemtype => $item_type })->store();
        step( "Add $item_type item type" );
    } else {
        step( "Add $item_type item type [SKIPPED]" );
    }
}

sub step {
    my ($message) = @_;

    print STDOUT "* $message\n";
}

1;
