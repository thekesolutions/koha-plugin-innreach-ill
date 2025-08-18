# koha-plugin-innreach

[![CI](https://github.com/thekesolutions/koha-plugin-innreach-ill/actions/workflows/main.yml/badge.svg)](https://github.com/thekesolutions/koha-plugin-innreach-ill/actions/workflows/main.yml)

INN-Reach inter-library loan service integration plugin for Koha.
This plugin implements the required API, ILL backend and tools to make
Koha able to be part of ILL networks using the INN-Reach service.

## Record/data contribution

A convenient script that allows to manually contribute things is added. For running it
or checking the available options, just run:

```shell
  sudo koha-shell <instance>
  cd /var/lib/koha/<instance>/plugins
  PERL5LIB=/usr/share/koha/lib:. perl \
            Koha/Plugin/Com/Theke/INNReach/scripts/contribute_data.pl --help
```

## Owning site

This plugin implements the full squence diagram included in the INN-Reach spec.
It is done in the form of a Koha ILL backend.

Some transitions are triggered through the UI (through the ILL module), and others
by API interactions.

## Borrowing site

This plugin implements the full squence diagram included in the INN-Reach spec.
It is done in the form of a Koha ILL backend.

Some transitions are triggered through the UI (through the ILL module), and others
by API interactions.

## Preparation

This plugin requires Koha version *22.11* or higher.

### Settings

* Enable *RESTOAuth2ClientCredentials* syspref
* Create an *ILL* patron category
* Create a patron for INN-Reach. Required permissions: *circulate* and *borrowers*.
* Create an API client_id/client_secret pair

### ILL

ILL needs to be set in *koha-conf.xml* (replace *${INSTANCE}* for your instance name):

```xml
<interlibrary_loans>
     <!-- Path to where Illbackends are located on the system
          - This setting should normally not be touched -->
     <backend_directory>/var/lib/koha/${INSTANCE}/plugins/Koha/Illbackends</backend_directory>
     <branch>M</branch>
     <!-- How should we treat staff comments?
          - hide: don't show in OPAC
          - show: show in OPAC -->
     <staff_request_comments>hide</staff_request_comments>
     <!-- How should we treat the reply_date field?
          - hide: don't show this field in the UI
          - any other string: show, with this label -->
     <reply_date>hide</reply_date>
     <!-- Where should digital ILLs be sent?
          - borrower: send it straight to the borrower email
          - branch: send the ILL to the branch email -->
     <digital_recipient>branch</digital_recipient>
     <!-- What patron category should we use for p2p ILL requests?
          - By default this is set to 'ILLLIBS' -->
     <partner_code>ILL</partner_code>
 </interlibrary_loans>
 ```

Then **enable** the *ILLModule* system preference.

## Install the plugin/ILL backend

Download the latest *.kpz* file from the [packages](https://gitlab.com/thekesolutions/plugins/koha-plugin-innreach/-/packages) page.
Install it as any other plugin following the general [plugin install instructions](https://wiki.koha-community.org/wiki/Koha_plugins).

## Plugin configuration

The plugin configuration is an HTML text area in which a *YAML* structure is pasted. The available options
are maintained on this document.

```yaml
---
d2ir:
    api_base_url: https://rssandbox-api.iii.com
    api_token_base_url: https://rssandbox-api.iii.com
    client_id: a_client_id
    client_secret: a_client_secret
    localServerCode: koha1
    mainAgency: code2
    require_patron_auth: true
    partners_library_id: ILL
    partners_category: IL
    library_to_location:
        CPL:
            location: code1
            description: Library 1
        MPL:
            location: code2
            description: Library 2
    local_to_central_itype:
        BK: 200
        CF: 201
        CR: 200
        MP: 200
        MU: 201
        MX: 201
        REF: 202
        VM: 201
    local_to_central_patron_type:
        AP: 200
        CH: 200
        DR: 200
        DR2: 200
        ILL: 202
        LIBSTAFF: 201
        NR: 200
        SR: 202
    central_to_local_itype:
        200: D2IR_BK
        201: D2IR_CF
    no_barcode_central_itypes:
        - 201
        - 202
    contribution:
        enabled: true
        max_retries: 10
        exclude_empty_biblios: true
        use_holding_library: false # if true, holding library will be used for the location
        included_items:
            biblionumber: [ 1, 2, 3 ]
            ccode: [ a, b, c ]
        excluded_items:
            biblionumber: [ 1, 2, 3 ]
            ccode: [ a, b, c ]
    # Default values for biblios/items configuration
    default_marc_framework: FA
    default_barcode_normalizers:
        - remove_all_spaces
        - trim
        - ltrim
        - rtrim
    borrowing:
        automatic_item_in_transit: false
        automatic_item_receive: false
    lending:
        automatic_final_checkin: false
        automatic_item_shipped: false
        automatic_item_shipped_debug: false
    default_item_type: ILL
    default_item_ccode: GENERAL_STACKS
    default_notforloan: -1 | null
    materials_specified: true
    default_materials_specified: Additional processing required (ILL)
    default_location:
    default_checkin_note: Additional processing required (ILL)
    default_hold_note: Placed by ILL
    # Patron validation restrictions
    debt_blocks_holds: true
    max_debt_blocks_holds: 100
    expiration_blocks_holds: true
    restriction_blocks_holds: true
    # Debugging
    debug_mode: false
    debug_requests: false
    dev_mode: false
    default_retry_delay: 120
```

### Options

* **centralServers**: This is a list of INN-Reach central servers. A Koha instance can be part of more than one ILL network, so several can be specified. No specific business rules are designed to be set for each of them (yet) but there's room for that. The code is designed to act against a specific central server. i.e. the one that initiates the circulation flow. Records and holdings contribution are designed to be done for all configured central servers with no options to specify what is contributed where.
* **localServerCode**: INN-Reach will assign a code to each server interacting with them. So each Koha instance is assigned a code, and it needs to be specified here.
* **api_base_url**, **client_id** and **client_secret**: This information needs to be provided by INN-Reach for the kick-off. It's the base URL into which Koha will make the API requests, and the id/secret pair for the *OAuth2 client credentials* flow.
* **require_patron_auth**: Whether or not we require the patron to input their credentials on the INN-Reach site. The code implement both use cases, but authenticating hasn't been tested on the wild due to the latency to set the environments. If there's a concrete use case we will have the chance to iron it.
* **local_patron_id**: This is the *borrowernumber* for the Koha user we created for INN-Reach to use (with permissions and API keys). This isn't supposed to be needed, but depending on the Koha version it wasn't possible to get the current patron from the stash. FIXME: This workaround should be removed once we are sure Koha *18.11.x* is fixed (patched in master by us).
* **library_to_location**: INN-Reach defines unique codes for locations. *library_to_location* is a hash for mapping Koha's branchcodes to location key codes. It includes the *location* but also the *description* attribute, which will be used for rendering dropdowns on INN-Reach. See the [kick-off checklist](#kick-off-checklist).
* **local_to_central_itype**: Hash for mapping Koha's itemtype codes to INN-Reach-defined ones. See the [kick-off checklist](#kick-off-checklist).
* **central_to_local_itype**: Hash for mapping central server's item types into locally defined ones. This is useful for being able to define special circ rules for each material type that comes via ILL. It defaults to the value from **default_item_type** if not defined.
* **local_to_central_patron_type**: Hash for mapping Koha's patron categories into INN-Reach-defined ones. See the [kick-off checklist](#kick-off-checklist).
* **contribution**: Data contribution specific settings. *max_retries* defines how many retries are to be accepted before failing to contribute a record/item.
* **debt_blocks_holds** and **max_debt_blocks_holds**: This settings are curently used on patron validation. If **debt_blocks_holds** is set to `true`, then **max_debt_blocks_holds** will be used to determine if the patron *owes more than allowed*. If the latter is not set, the plugin will fallback to the `maxoutstanding` system preference.

*Note*: Central patron types and central item types can be fetched using the defined methods
using the Contribution class.

## Kick-off checklist

### Agency codes

The concept of agency is tied in INN-Reach to each 'institution'. Koha has the ability to model different library organizations using the libraries/branches separation. If they are branches of the same institution (1), INN-Reach will assign a single *agency code* to the whole Koha instance. If Koha is representing many institutions as in-a-consortia, then those would be assigned many agency codes (2).

Koha does not currently handle the latter, with branches on them.

TODO: Do we need a way to handle multiple agency codes, for (2) on this analysis?
TODO: Could we model this using library groups?

### Locations

Each branch in Koha, can be thought about as a location or pickup location. That's how Koha actually behaves now. For the kick-off, the institution needs to defined which (Koha) branches will participate on the INN-Reach system, and generate the mappings.

Mappings require a *location* code and *description* for each participating branch:

```yaml
CPL:
  location: centerv
  description: Centerville Community Library
MPL:
  location: midway
  description: Midway Public Library
```

### Item types

INN-Reach defines unique ids to item types based on the exchange with the different insitutions using the central server. An exchange needs to take place to either adjust the mapping to the existing item types (if the Koha instance is joining a previsouly existing INN-Reach central server) or to suggest a list of itemtypes matching Koha's. The mapping needs to be done anyway, as Koha uses strings, and they use integers.

You can check the defined central server item types by running:

```shell
  $ sudo koha-shell <instance>
  $ cd /var/lib/koha/<instance>/plugins
  $ PERL5LIB=/usr/share/koha/lib:. perl \
                Koha/Plugin/Com/Theke/INNReach/scripts/get_central_servers_data.pl --item_types
```

### Patron types

INN-Reach defines unique ids to patron types based on the exchange with the different insitutions using the central server. An exchange needs to take place to either adjust the mapping to the existing patron types (if the Koha instance is joining a previsouly existing INN-Reach central server) or to suggest a list of patron types matching Koha's. The mapping needs to be done anyway, as Koha uses strings, and they use integers.

You can check the defined central server item types by running:

```shell
  $ sudo koha-shell <instance>
  $ cd /var/lib/koha/<instance>/plugins
  $ PERL5LIB=/usr/share/koha/lib:. perl \
                Koha/Plugin/Com/Theke/INNReach/scripts/get_central_servers_data.pl --patron_types
```

## Setting initial locations

The use case covered by this implementation is that locations are Koha's branches (i.e. they are really pickup locations).
One of the first configuration steps is to populate INN-Reach with our current locations. Use the *contribute_data.pl* for that:

```shell
  $ sudo koha-shell <instance>
  $ cd /var/lib/koha/<instance>/plugins
  $ PERL5LIB=/usr/share/koha/lib:. perl \
                Koha/Plugin/Com/Theke/INNReach/scripts/contribute_data.pl \
                --central_server d2ir \
                --overwrite_locations
```

You can retrieve the central server locations (e.g. to check things went corretly):

```shell
  $ PERL5LIB=/usr/share/koha/lib:. perl \
                Koha/Plugin/Com/Theke/INNReach/scripts/get_central_servers_data.pl --locations
```

## Setting the task queue daemon

The task queue daemon will process any actions that are scheduled to be run. This are usually biblio/items
updates to be notified to central servers, but also some other circulation notifications like 'borrowerrenew'.

To run it:

```shell
# copy unit file
$ cp /var/lib/koha/<instance>/plugins/Koha/Plugin/Com/Theke/INNReach/scripts/innreach_task_queue.service \
     /etc/systemd/system/innreach_task_queue.service
# set KOHA_INSTANCE to match what you need (default: kohadev)
$ vim /etc/systemd/system/innreach_task_queue.service
# reload unit files, including the new one
$ systemctl daemon-reload
# enable service
$ systemctl enable innreach_task_queue.service
Created symlink /etc/systemd/system/multi-user.target.wants/innreach_task_queue.service → /etc/systemd/system/innreach_task_queue.service
# check the logs :-D
$ journalctl -u innreach_task_queue.service -f

```

## Initial record contribution

Contribution rules are likely needed to be set before starting to use the plugin.

**WARNING:** Not setting any rules will make Koha contribute every record.

Before starting the contribution setup, we recommend setting the `contribution / enabled` setting to `false`. To avoid leaking the wrong records and items to the configured central server.

Once the contribution rules are set (either `included_items` or `excluded_items`) it is time to
perform the first contribution.

For that, we will use the `sync_bibliographic_data.pl` script:

```shell
  $ sudo koha-shell <instance>
  $ cd /var/lib/koha/<instance>/plugins
  $ PERL5LIB=/usr/share/koha/lib:. perl \
                Koha/Plugin/Com/Theke/INNReach/scripts/sync_bibliographic_data.pl \
                --central_server d2ir \
                --limit 10 \
                --where "SOME_SQL_CONDITION"
```

Both `--limit` and `--where` can be handy for some initial testing.

### Recontribution

The `sync_bibliographic_data.pl` script first decontributes the biblios inside the main loop
so for recontribution (for example, when rules are changed) you should just run the script
with the needed constraints.

## Slip printing

The plugin implements the `notices_content` hook to make ILL-related information available to notices.

### HOLD_SLIP

On this letter, the plugin makes this attributes available.

* `[% plugin_content.innreach.ill_request | html %]`
* `[% plugin_content.innreach.itemId | html %]`
* `[% plugin_content.innreach.pickupLocation | html %]`
* `[% plugin_content.innreach.patronName | html %]`
* `[% plugin_content.innreach.centralPatronType | html %]`

The `ill_request` attribute will only be available if the plugin finds the hold is linked to
a valid INN-Reach ILL request. It should be used to detect the ILL context for displaying
ILL specific messages.

For example:

```
[% IF plugin_content.innreach.ill_request  %]
<ul>
    <li>ILL request ID: [% plugin_content.innreach.ill_request.id | html %]</li>
    <li>Item ID: [% plugin_content.innreach.itemId | html %]</li>
    <li>Pickup location: [% plugin_content.innreach.pickupLocation | html %]</li>
    <li>Patron name: [% plugin_content.innreach.patronName | html %]</li>
    <li>Central patron type: [% plugin_content.innreach.centralPatronType | html %]</li>
<ul>
[% END %]
```

## Caveats

Koha doesn't have a proper way to *move a hold* from one item/biblio to another. So there's no UI allowing to trigget the
*transferrequest* flow on the owning site. The borrowing site does implement the route, though. So Koha accepts *transferrequest*
and can act accordingly, but it needs to be generated from another third party server.
