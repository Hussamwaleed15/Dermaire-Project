import os
from collections.abc import Mapping
from app.core.config import settings
from app.core.observability import observed_dependency

class AzureBlobService:
    def __init__(self):
        self.is_live = settings.is_blob_live
        if self.is_live:
            from azure.storage.blob import BlobServiceClient
            try:
                self.client = BlobServiceClient.from_connection_string(settings.AZURE_STORAGE_CONNECTION_STRING, connection_timeout=5, read_timeout=10, retry_total=2)
                if not self.client.url.startswith("https://"):
                    raise ValueError("HTTPS storage required")
                self.container_client = self.client.get_container_client(settings.AZURE_STORAGE_CONTAINER)
            except ValueError:
                # Bad configuration is degraded, never a local persistence fallback.
                self.client = self.container_client = None
        else:
            self.local_upload_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "uploads"))
            os.makedirs(self.local_upload_dir, exist_ok=True)

    def require_private(self, **probe_options):
        if not self.is_live:
            raise RuntimeError("Real image storage unavailable")
        if self.container_client.get_container_properties(**probe_options).get("public_access"):
            raise RuntimeError("Image storage must be private")

    @staticmethod
    def _property(value, name):
        """Azure properties may contain mappings, SDK models, or absent policies."""
        if isinstance(value, Mapping):
            return value.get(name)
        return getattr(value, name, None)

    @classmethod
    def _has_retention_or_versioning(cls, properties):
        return any(
            cls._property(cls._property(properties, name), "enabled")
            for name in ("delete_retention_policy", "container_delete_retention_policy")
        ) or bool(cls._property(properties, "is_versioning_enabled"))

    def health(self):
        if not self.is_live:
            return {"provider": "none", "state": "unconfigured", "durable_images": False}
        try:
            probe_options = {"connection_timeout": 3, "read_timeout": 3, "retry_total": 0}
            self.require_private(**probe_options)
            properties = self.client.get_service_properties(**probe_options)
            if self._has_retention_or_versioning(properties):
                raise RuntimeError("Retention incompatible with deletion")
            return {"provider": "azure_blob", "state": "available", "durable_images": True,
                    "probe": "private_container_metadata", "end_to_end_verified": False,
                    "versioning_policy": "requires_infrastructure_verification"}
        except Exception:
            return {"provider": "azure_blob", "state": "degraded", "durable_images": False}

    @observed_dependency("blob_upload")
    def upload_capture(self, blob_name: str, data: bytes) -> None:
        """Private real storage only; no local fallback and no SAS generation."""
        self.require_private()
        properties = self.client.get_service_properties()
        if self._has_retention_or_versioning(properties):
            raise RuntimeError("Storage retention incompatible with image cleanup")
        from azure.storage.blob import ContentSettings
        result = self.container_client.get_blob_client(blob_name).upload_blob(
            data, overwrite=True, content_settings=ContentSettings(content_type="image/png"))
        if isinstance(result, dict) and result.get("version_id"):
            raise RuntimeError("Versioned storage requires infrastructure repair before uploads")

    @observed_dependency("blob_read")
    def read_capture(self, blob_name: str) -> bytes:
        self.require_private()
        return self.container_client.get_blob_client(blob_name).download_blob().readall()

    def delete_owned_images(self, owner_id: str) -> None:
        # Namespaced uploads also cover files whose subsequent DB save failed.
        if self.is_live:
            names = [blob.name for blob in self.container_client.list_blobs(name_starts_with=f"skin_photos/{owner_id}/", include=["deleted", "versions"])]
        else:
            names = [name for name in os.listdir(self.local_upload_dir) if name.startswith(f"{owner_id}_")]
        for name in names:
            self.delete_image(name)

    @observed_dependency("blob_delete")
    def delete_image(self, blob_name: str) -> None:
        # Inconsistent legacy URLs require repair, never publish/follow them.
        if any(character in blob_name for character in (":", "?", "#")):
            raise ValueError("Invalid stored image reference")
        # Missing files are already cleaned up; other errors must reach the caller.
        if self.is_live:
            from azure.core.exceptions import ResourceNotFoundError
            properties = self.client.get_service_properties()
            if self._has_retention_or_versioning(properties):
                raise RuntimeError("Storage retention prevents confirmed permanent deletion")
            # Historical versions/deleted blobs may remain after retention was
            # disabled. Do not claim completion while those copies still exist.
            for blob in self.container_client.list_blobs(name_starts_with=blob_name, include=["deleted", "versions"]):
                if blob.name == blob_name and (blob.deleted or blob.version_id):
                    raise RuntimeError("Owned historical blob copies require permanent cleanup")
            try:
                self.container_client.delete_blob(blob_name, delete_snapshots="include")
            except ResourceNotFoundError:
                pass
            for blob in self.container_client.list_blobs(name_starts_with=blob_name, include=["deleted", "versions"]):
                if blob.name == blob_name:
                    raise RuntimeError("Blob copies remain after deletion")
        else:
            filename = os.path.basename(blob_name)
            if not filename or filename in (".", ".."):
                raise ValueError("Invalid owned blob name")
            try:
                os.remove(os.path.join(self.local_upload_dir, filename))
            except FileNotFoundError:
                if blob_name.count("/") >= 2:
                    raise RuntimeError("Azure cleanup unavailable; configure storage before retrying")


azure_blob_service = AzureBlobService()
