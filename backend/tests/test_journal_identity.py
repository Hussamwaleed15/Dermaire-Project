from unittest.mock import patch
import pytest
from app.core.config import settings
from app.services.deletion_journal import DeletionJournal


def test_identity_uses_selected_credential():
    with patch.object(settings, 'DELETION_JOURNAL_ACCOUNT_URL', 'https://example.blob.core.windows.net'), patch.object(settings, 'DELETION_JOURNAL_CONNECTION_STRING', ''), patch.object(settings, 'DELETION_JOURNAL_MANAGED_IDENTITY_CLIENT_ID', 'synthetic-client'), patch('azure.identity.ManagedIdentityCredential') as credential, patch('azure.storage.blob.BlobServiceClient') as client:
        journal = DeletionJournal(key='k' * 32, required=True)
        credential.assert_called_once_with(client_id='synthetic-client')
        assert client.call_args.kwargs['credential'] is credential.return_value
        assert journal.container is client.return_value.get_container_client.return_value


def test_identity_rejects_ambiguous_or_insecure_configuration():
    for url, connection in [('http://example', ''), ('https://example', 'synthetic'),
                            ('https://example/?sig=synthetic', ''),
                            ('https://user:synthetic@example', ''),
                            ('https://example/container', '')]:
        with patch.object(settings, 'DELETION_JOURNAL_ACCOUNT_URL', url), patch.object(settings, 'DELETION_JOURNAL_CONNECTION_STRING', connection), pytest.raises(ValueError):
            DeletionJournal(key='k' * 32, required=True)
