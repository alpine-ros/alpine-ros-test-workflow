import os
import sys
import yaml

if len(sys.argv) != 5:
    print('Usage: update-distribution.py path_to_distribution_yaml meta_package version revision')
    sys.exit(1)

path_to_distribution_yaml = sys.argv[1]
meta_package = sys.argv[2]
version = sys.argv[3]
revision = sys.argv[4]

with open(path_to_distribution_yaml, 'r') as f:
    data = yaml.load(f, Loader=yaml.FullLoader)

if data['repositories'] is not None and meta_package in data['repositories']:
    data['repositories'][meta_package]['release']['version'] = f'{version}-{revision}'
else:
    if 'ROS_DISTRO' not in os.environ:
        print('ROS_DISTRO is required')
        sys.exit(1)
    if 'SOURCE_REPO_URL' not in os.environ:
        print('SOURCE_REPO_URL is required')
        sys.exit(1)
    if 'SOURCE_BRANCH' not in os.environ:
        print('SOURCE_BRANCH is required')
        sys.exit(1)
    if 'RELEASE_REPO_URL' not in os.environ:
        print('RELEASE_REPO_URL is required')
        sys.exit(1)
    if 'PACKAGES' not in os.environ:
        print('PACKAGES is required')
        sys.exit(1)

    ros_distro = os.environ['ROS_DISTRO']

    if data['repositories'] is None:
        data['repositories'] = dict()
    data['repositories'][meta_package] = dict()
    data['repositories'][meta_package]['doc'] = dict()
    data['repositories'][meta_package]['doc']['type'] = 'git'
    data['repositories'][meta_package]['doc']['url'] = os.environ['SOURCE_REPO_URL']
    data['repositories'][meta_package]['doc']['version'] = os.environ['SOURCE_BRANCH']
    data['repositories'][meta_package]['release'] = dict()
    data['repositories'][meta_package]['release']['tags'] = dict()
    data['repositories'][meta_package]['release']['tags']['release'] = f'release/{ros_distro}/{{package}}/{{version}}'
    data['repositories'][meta_package]['release']['url'] = os.environ['RELEASE_REPO_URL']
    data['repositories'][meta_package]['release']['version'] = f'{version}-{revision}'
    data['repositories'][meta_package]['source'] = dict()
    data['repositories'][meta_package]['source']['type'] = 'git'
    data['repositories'][meta_package]['source']['url'] = os.environ['SOURCE_REPO_URL']
    data['repositories'][meta_package]['source']['version'] = os.environ['SOURCE_BRANCH']
    data['repositories'][meta_package]['status'] = 'developed'

if 'PACKAGES' in os.environ:
    pkgs = sorted(os.environ['PACKAGES'].split())
    if len(pkgs) > 1 or pkgs[0] != meta_package:
      data['repositories'][meta_package]['release']['packages'] = pkgs
    else:
      data['repositories'][meta_package]['release'].pop('packages', None)

with open(path_to_distribution_yaml, 'w') as f:
    f.write('''%YAML 1.1
# ROS distribution file
# see REP 143: http://ros.org/reps/rep-0143.html
---
''')
    f.write(yaml.dump(data, default_flow_style=False))
