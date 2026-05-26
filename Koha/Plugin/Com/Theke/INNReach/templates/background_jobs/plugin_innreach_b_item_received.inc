[% USE Koha %]

[% SET report = job.decoded_data %]
[% BLOCK report %]
    [% IF job.status == 'finished' %]
        [% IF report %]
            <div class="dialog message">
                The item has been notified as received correctly.
            </div>
        [% ELSE %]
            <div class="dialog message">
               Job data could not be read, see the logs for details
            </div>
        [% END %]
    [% ELSIF job.status == 'cancelled' %]
        <span>The job has been cancelled before it finished.</span>
    [% END %]
[% END %]

[% BLOCK detail %]
    [% FOR m IN job.messages %]
        <div class="dialog message">
            [% IF m.type == 'success' %]
                <i class="fa fa-check success"></i>
            [% ELSIF m.type == 'warning' %]
                <i class="fa-solid fa-triangle-exclamation warn"></i>
            [% ELSIF m.type == 'error' %]
                <i class="fa fa-exclamation error"></i>
            [% END %]
            [% SWITCH m.code %]
                [% CASE 'request_failed' %]
                    <span>Error sending <b>[% m.method | html %]</b> request: [% m.response | html %]</span>
                    [% IF m.method == 'item_received' %]
                        <form method="post" action="/cgi-bin/koha/ill/ill-requests.pl" style="margin-top: 1em;">
                            <input type="hidden" name="ill_request_id" value="[% report.ill_request_id | html %]" />
                            <input type="hidden" name="op" value="innreach_item_received_override" />
                            <label>
                                <input type="checkbox" name="skip_api_request" value="1" />
                                Mark as received regardless (skip central server notification)
                            </label>
                            <button type="submit" class="btn btn-warning btn-sm" style="margin-left: 0.5em;">
                                <i class="fa fa-check"></i> Force mark as received
                            </button>
                        </form>
                    [% END %]
            [% CASE %]
                    <span>Unhandled error: [% m.error | html %]</span>
            [% END %]
        </div>
    [% END %]
[% END %]


[% BLOCK js %]
[% END %]
