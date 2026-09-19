from pathlib import Path
import re

path = Path('lib/core/config/carto_basemap_config.dart')
if path.exists():
    text = path.read_text(encoding='utf-8')
    text = re.sub(r'R58[A-Z0-9]{8}', 'DEVICE_ID', text)
    path.write_text(text, encoding='utf-8')
