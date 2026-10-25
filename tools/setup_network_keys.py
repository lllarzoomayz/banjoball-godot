"""Generate server-only keys and the pinned public certificate. Never print secrets."""
from pathlib import Path
import datetime, secrets
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID

root=Path(__file__).resolve().parents[1]
data=root/'server/data';data.mkdir(parents=True,exist_ok=True)
public=root/'assets/network';public.mkdir(parents=True,exist_ok=True)
if not (data/'server.key').exists():
    key=rsa.generate_private_key(public_exponent=65537,key_size=3072)
    name=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'banjoball.lan')])
    now=datetime.datetime.now(datetime.timezone.utc)
    cert=(x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
          .serial_number(x509.random_serial_number()).not_valid_before(now-datetime.timedelta(days=1))
          .not_valid_after(now+datetime.timedelta(days=3650))
          .add_extension(x509.SubjectAlternativeName([x509.DNSName('banjoball.lan')]),critical=False)
          .add_extension(x509.BasicConstraints(ca=True,path_length=0),critical=True)
          .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]),critical=False)
          .sign(key,hashes.SHA256()))
    (data/'server.key').write_bytes(key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
    (data/'server.crt').write_bytes(cert.public_bytes(serialization.Encoding.PEM))
if not (data/'service.key').exists():(data/'service.key').write_text(secrets.token_urlsafe(48),encoding='ascii')
(public/'server.crt').write_bytes((data/'server.crt').read_bytes())
print('Server keys retained in server/data; public trust certificate in assets/network.')
