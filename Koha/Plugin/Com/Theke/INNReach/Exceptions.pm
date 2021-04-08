package Koha::Plugin::Com::Theke::INNReach::Exceptions;

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

use Exception::Class (
  'INNReach::Ill',
  'INNReach::Ill::InconsistentStatus'   => { isa => 'INNReach::Ill', fields => ['expected_status'] },
  'INNReach::Ill::InvalidCentralserver' => { isa => 'INNReach::Ill', fields => ['central_server'] },
  'INNReach::Ill::MissingParameter'     => { isa => 'INNReach::Ill', fields => ['param'] },
  'INNReach::Ill::UnknownItemId'        => { isa => 'INNReach::Ill', fields => ['item_id'] },
  'INNReach::Ill::UnknownBiblioId'      => { isa => 'INNReach::Ill', fields => ['biblio_id'] }
);

1;
