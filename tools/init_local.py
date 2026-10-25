"""Initialize a separate local deployment without overwriting existing settings."""
from pathlib import Path
import shutil, subprocess, sys
root=Path(__file__).resolve().parents[1]
for example, target in [('server/config.example.json','server/config.json'),
                        ('assets/network/endpoints.example.json','assets/network/endpoints.json')]:
    dest=root/target
    if not dest.exists():shutil.copy2(root/example,dest)
subprocess.run([sys.executable,str(root/'tools/setup_network_keys.py')],check=True,cwd=root)
print('Local deployment initialized. Keep server/data and signing keys private.')
