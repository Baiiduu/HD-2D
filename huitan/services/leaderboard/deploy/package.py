"""Create a content-addressed Linux release, without runtime files or credentials."""
import argparse
import gzip
import hashlib
from io import BytesIO
import json
from pathlib import Path
import tarfile


def build(source: Path, output: Path) -> Path:
    source, output = source.resolve(), output.resolve()
    if output.is_relative_to(source):
        raise ValueError('Release output must be outside the service source directory')
    files = [source / 'requirements.txt', source / 'requirements-linux.lock',
             *sorted((source / 'leaderboard').glob('*.py'))]
    files += sorted(path for path in (source / 'deploy').glob('*')
                    if path.suffix in {'.py', '.sh', '.service', '.conf'})
    contents = {}
    for path in files:
        if path.is_symlink() or not path.resolve().is_relative_to(source):
            raise ValueError('Release inputs must not be symlinks')
        contents[path.relative_to(source).as_posix()] = path.read_bytes()
    hashes = {name: hashlib.sha256(data).hexdigest() for name, data in contents.items()}
    release = hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()[:16]
    contents['release.json'] = json.dumps({'release': release, 'files': hashes}, sort_keys=True).encode()
    output.mkdir(parents=True, exist_ok=True)
    target = output / f'leaderboard-{release}.tar.gz'
    with target.open('wb') as raw, gzip.GzipFile(fileobj=raw, filename='', mode='wb', mtime=0) as packed:
        with tarfile.open(fileobj=packed, mode='w') as archive:
            for name, data in sorted(contents.items()):
                info = tarfile.TarInfo(name)
                info.size = len(data)
                info.mode = 0o755 if name.endswith('.sh') else 0o644
                archive.addfile(info, BytesIO(data))
    return target


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    artifact = build(Path(__file__).resolve().parents[1], args.output)
    print(json.dumps({'artifact': str(artifact), 'sha256': hashlib.sha256(artifact.read_bytes()).hexdigest()}))
