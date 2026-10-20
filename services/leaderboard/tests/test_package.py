import importlib.util
from pathlib import Path
import tarfile

import pytest


def module():
    path = Path(__file__).parents[1] / 'deploy' / 'package.py'
    spec = importlib.util.spec_from_file_location('release_package', path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def test_package_excludes_credentials_runtime_and_tests(tmp_path):
    source = tmp_path / 'service'
    (source / 'leaderboard').mkdir(parents=True)
    (source / 'deploy').mkdir()
    (source / 'leaderboard' / 'app.py').write_text('app = None\n')
    (source / 'requirements.txt').write_text('example==1\n')
    (source / 'requirements-linux.lock').write_text('example==1\n')
    (source / '.env').write_text('SECRET=never-package-this\n')
    (source / 'deploy' / 'production.env').write_text('SECRET=private\n')
    package = module()
    artifact = package.build(source, tmp_path / 'out')
    with tarfile.open(artifact) as archive:
        names = archive.getnames()
        assert 'leaderboard/app.py' in names
        assert '.env' not in names and 'deploy/production.env' not in names
        assert 'release.json' in names
        assert 'requirements-linux.lock' in names
        assert all(not name.startswith('/') and '..' not in name.split('/') for name in names)
    same = package.build(source, tmp_path / 'out2')
    assert artifact.name == same.name and artifact.read_bytes() == same.read_bytes()


def test_package_rejects_output_inside_source(tmp_path):
    with pytest.raises(ValueError):
        module().build(tmp_path, tmp_path / 'output')
