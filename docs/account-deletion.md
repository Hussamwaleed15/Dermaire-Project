# Account deletion

DELETE /api/v1/users/me requires a valid, unexpired access token and returns
204 only after external cleanup and the database transaction both complete.
An absent account returns 204 for a safely authenticated retry. Other routes
reject tokens for deleted users. Refresh and doctor QR tokens are not accepted
as account credentials.

The lifecycle removes check-ins, experiments, products, redemptions, clinical
notes involving the account, doctor grants in either direction, and the user.
Audit events retain action, resource type and timestamp; associated details and
IP addresses are removed and the deleted actor gets a keyed pseudonym.

Images recorded on legacy check-ins are removed by their stored blob name.
New uploads use an authenticated user namespace; deleting that namespace also
removes uploads orphaned by a later failed DB save. Arbitrary product image
URLs are external references, not evidence of owned storage. Old orphan files
without an ownership record cannot safely be attributed to a user.

Blob deletes include snapshots, ignore only absent blobs, and propagate other
storage failures. Ownership records remain on any cleanup or DB failure, so a
retry can finish safely. Some images may already be gone after partial failure;
this is an unavoidable consequence of deleting across separate storage systems.
No success is reported in that case. User-row locking serializes authenticated
requests and deletion on databases supporting row locks. SQLite is for local
use and does not provide the production row-lock guarantee.

Flutter accepts only the completed 204 response. Failed/network/pending responses
preserve authentication and account state. Confirmed deletion removes stored
credentials, product cache and safety acceptance, clears account memory, and
opens the welcome screen with the previous navigation history removed.

Azure soft-delete/version retention is an infrastructure setting. Cleanup fails
closed if retention/versioning is enabled or historical/deleted owned copies
are listed; it does not report deletion success. Operators must configure the
storage account for permanent deletion and resolve historical copies before
retrying. The application never changes account-wide retention settings.
