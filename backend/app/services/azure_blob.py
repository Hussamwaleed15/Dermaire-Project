import os
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional, Tuple
from app.core.config import settings

class AzureBlobService:
    def __init__(self):
        self.is_live = settings.is_blob_live
        if self.is_live:
            from azure.storage.blob import BlobServiceClient
            self.client = BlobServiceClient.from_connection_string(settings.AZURE_STORAGE_CONNECTION_STRING)
            self.container_client = self.client.get_container_client(settings.AZURE_STORAGE_CONTAINER)
            try:
                self.container_client.create_container()
            except Exception:
                pass
        else:
            self.local_upload_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "uploads"))
            os.makedirs(self.local_upload_dir, exist_ok=True)

    def upload_image(self, file_bytes: bytes, original_filename: str, content_type: str = "image/jpeg", owner_id: str = None) -> Tuple[str, str]:
        ext = os.path.splitext(original_filename)[1] or ".jpg"
        if not owner_id or any(c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-" for c in owner_id):
            raise ValueError("An authenticated owner is required for uploads")
        blob_name = f"skin_photos/{owner_id}/{owner_id}_{uuid.uuid4()}{ext}"

        if self.is_live:
            from azure.storage.blob import ContentSettings
            blob_client = self.container_client.get_blob_client(blob_name)
            blob_client.upload_blob(file_bytes, overwrite=True, content_settings=ContentSettings(content_type=content_type))
            sas_url = self.generate_sas_url(blob_name)
            return blob_name, sas_url
        else:
            local_path = os.path.join(self.local_upload_dir, os.path.basename(blob_name))
            with open(local_path, "wb") as f:
                f.write(file_bytes)
            return blob_name, f"/api/v1/static/uploads/{os.path.basename(blob_name)}"

    def delete_owned_images(self, owner_id: str) -> None:
        # Namespaced uploads also cover files whose subsequent DB save failed.
        if self.is_live:
            names = [blob.name for blob in self.container_client.list_blobs(name_starts_with=f"skin_photos/{owner_id}/", include=["deleted", "versions"])]
        else:
            names = [name for name in os.listdir(self.local_upload_dir) if name.startswith(f"{owner_id}_")]
        for name in names:
            self.delete_image(name)

    def delete_image(self, blob_name: str) -> None:
        # Missing files are already cleaned up; other errors must reach the caller.
        if self.is_live:
            from azure.core.exceptions import ResourceNotFoundError
            properties = self.client.get_service_properties()
            if properties.get("delete_retention_policy", {}).get("enabled") or properties.get("is_versioning_enabled"):
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
        else:
            filename = os.path.basename(blob_name)
            if not filename or filename in (".", ".."):
                raise ValueError("Invalid owned blob name")
            try:
                os.remove(os.path.join(self.local_upload_dir, filename))
            except FileNotFoundError:
                pass

    def generate_sas_url(self, blob_name: str, expiry_minutes: int = 30) -> str:
        if not self.is_live:
            return f"/api/v1/static/uploads/{os.path.basename(blob_name)}"

        from azure.storage.blob import generate_blob_sas, BlobSasPermissions
        sas_token = generate_blob_sas(
            account_name=self.client.account_name,
            container_name=settings.AZURE_STORAGE_CONTAINER,
            blob_name=blob_name,
            account_key=self.client.credential.account_key,
            permission=BlobSasPermissions(read=True),
            expiry=datetime.now(timezone.utc) + timedelta(minutes=expiry_minutes)
        )
        return f"https://{self.client.account_name}.blob.core.windows.net/{settings.AZURE_STORAGE_CONTAINER}/{blob_name}?{sas_token}"

azure_blob_service = AzureBlobService()
