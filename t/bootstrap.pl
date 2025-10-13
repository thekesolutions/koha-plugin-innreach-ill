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

use utf8;
binmode( STDOUT, ':encoding(UTF-8)' );
binmode( STDERR, ':encoding(UTF-8)' );

use DDP;
use File::Slurp;
use Try::Tiny qw(catch try);
use YAML::XS;

use C4::Context;
use Koha::Database;
use Koha::ItemTypes;
use Koha::Patron::Categories;

# For generating random data
use t::lib::TestBuilder;

use Koha::Plugin::Com::Theke::INNReach;

print STDOUT "\n=== INNReach Plugin Bootstrap ===\n\n";

my $builder = t::lib::TestBuilder->new;
my $plugin  = Koha::Plugin::Com::Theke::INNReach->new;

print STDOUT "System Preferences:\n";
C4::Context->set_preference( 'ILLModule', 1 )
    && step( "ILLModule enabled", 1 );

C4::Context->set_preference( 'RESTBasicAuth', 1 )
    && step( "RESTBasicAuth enabled", 1 );

print STDOUT "\nPlugin Configuration:\n";
my $dbh = C4::Context->dbh;

# Make sure the plugin is enabled
$dbh->do(
    q{
    UPDATE plugin_data SET plugin_value=1
    WHERE plugin_key='__ENABLED__'
      AND plugin_class='Koha::Plugin::Com::Theke::INNReach'
}
) && step( "INNReach plugin enabled", 1 );

$dbh->do(
    q{
    UPDATE plugin_data SET plugin_value=0
    WHERE plugin_key='__ENABLED__'
      AND plugin_class<>'Koha::Plugin::Com::Theke::INNReach'
}
) && step( "Other plugins disabled", 1 );

my $config_string = read_file('t/config.yaml');
$plugin->store_data(
    {
        configuration => $config_string,
    }
);
step( "Configuration loaded from t/config.yaml", 1 );

print STDOUT "\nLibraries:\n";
my $ill_library = Koha::Libraries->search( { branchcode => 'ILL' } )->next;
if ( !$ill_library ) {
    $builder->build_object(
        {
            class => 'Koha::Libraries',
            value => { branchcode => 'ILL', pickup_location => 1 }
        }
    );
    step( "ILL library created", 1 );
} else {
    step( "ILL library already exists", 1 );
}

print STDOUT "\nPatron Categories:\n";

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
    )
{
    if ( !Koha::Patron::Categories->search( { categorycode => $category_data->{categorycode} } )->count ) {
        Koha::Patron::Category->new(
            {
                categorycode          => $category_data->{categorycode},
                description           => $category_data->{description},
                enrolmentperiod       => 99,
                upperagelimit         => 999,
                dateofbirthrequired   => 0,
                enrolmentfee          => 0.00,
                overduenoticerequired => 0,
                reservefee            => 0.00,
                hidelostitems         => 0,
                category_type         => 'A'
            }
        )->store();
        step( "$category_data->{categorycode} category created", 1 );
    } else {
        step( "$category_data->{categorycode} category already exists", 1 );
    }
}

print STDOUT "\nItem Types:\n";
foreach my $item_type (qw(D2IR_BK D2IR_CF)) {

    if ( !Koha::ItemTypes->search( { itemtype => $item_type } )->count ) {
        Koha::ItemType->new( { itemtype => $item_type } )->store();
        step( "$item_type item type created", 1 );
    } else {
        step( "$item_type item type already exists", 1 );
    }
}

print STDOUT "\nAgency Patrons:\n";

# Create agency patrons from agencies.yaml
my $agencies_config = YAML::XS::LoadFile('t/agencies.yaml');

foreach my $agency ( @{ $agencies_config->{agencies} } ) {
    my $cardnumber = "AGENCY_" . uc( $agency->{agency_code} );
    my $userid     = lc( $agency->{agency_code} ) . "_agency";

    # Check if patron already exists
    my $existing_patron = Koha::Patrons->search( { cardnumber => $cardnumber } )->next;

    if ( !$existing_patron ) {
        my $patron = $builder->build_object(
            {
                class => 'Koha::Patrons',
                value => {
                    cardnumber   => $cardnumber,
                    userid       => $userid,
                    surname      => "Agency",
                    firstname    => $agency->{description},
                    categorycode => 'ILL',
                    branchcode   => 'ILL',
                    flags        => 1,                        # circulate permission
                }
            }
        );
        step( "$cardnumber created ($agency->{description})", 1 );
    } else {
        step( "$cardnumber already exists", 1 );
    }
}

print STDOUT "\n=== Bootstrap completed successfully ===\n";

sub step {
    my ( $message, $level ) = @_;
    $level //= 0;

    my $indent = "  " x $level;
    print STDOUT "$indent✓ $message\n";
}

1;
