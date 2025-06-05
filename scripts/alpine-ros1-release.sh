#!/bin/bash

set -eu

if ! echo 'import yaml' | python3 >/dev/null 2>/dev/null; then
  echo "This script requires PyYaml" >&2
  exit 1
fi

rosdistro_repo_slug=${ROSDISTRO_REPO_SLUG:-alpine-ros/rosdistro1}
rosdistro_repo=https://github.com/${rosdistro_repo_slug}.git
rosdistro_repo_branch=${ROSDISTRO_REPO_BRANCH:-main}
meta_package=${META_PACKAGE:-$(basename $(pwd))}

if [ $# -lt 4 ]; then
  cat <<EOS
Usage: $(basename $0) ROS_DISTRO SOURCE_REPO_SLUG RELEASE_REPO_SLUG ROSDISTRO_FORK_SLUG [REVISION]

Arguments:
  ROS_DISTRO:
    ROS distro name
    e.g. noetic
  SOURCE_REPO_SLUG:
    Package repository slug
    e.g. your-username/ros_package_name
  RELEASE_REPO_SLUG:
    Release repository slug to push release data
    e.g. your-username/ros_package_name-release
  ROSDISTRO_FORK_SLUG:
    Rosdistro repository slug to push PR branches
    You need to fork alpine-ros/rosdistro1 beforehand
    e.g. your-username/rosdistro1
  REVISION:
    Release revision number (default: 1)

Environments:
  ROSDISTRO_REPO_SLUG:
    Overwrite rosdistro repository slug
    current: ${rosdistro_repo_slug}
  ROSDISTRO_REPO_BRANCH:
    Overwrite base branch of the meta-package
    current: ${rosdistro_repo_branch}
  META_PACKAGE:
    Overwrite the meta-package name
    current: ${meta_package}
EOS
  exit 1
fi

ros_distro=$1
source_repo=https://github.com/$2.git
release_repo=https://github.com/$3.git
rosdistro_fork_slug=$4
rev=${5:-1}

rosdistro_push_repo=https://github.com/${rosdistro_fork_slug}.git
rosdistro_push_user=$(dirname ${rosdistro_fork_slug})

# Check repository status

if [ ! -z "$(git status --porcelain --untracked-files=no)" ]; then
  echo "The repository has uncommited changes!" >&2
  exit 1
fi

if [ "$(git rev-parse --show-toplevel)" != "$(pwd)" ]; then
  echo "This script must be run on the top directory of the repository!" >&2
  exit 1
fi

echo "=============================="
echo "Preparing releases:"
echo

# List and validate manifest files

base_branch=$(git rev-parse --abbrev-ref HEAD)
if [ ${base_branch} == "HEAD" ]; then
  base_branch=temporary/$(mktemp --dry-run XXXXXXXX)
  git checkout -b ${base_branch}
fi

manifests=$(find . -name package.xml)
ver_meta_pkg=
packages=
for m in ${manifests}; do
  dir=$(dirname ${m})
  pkg=$(sed ':a;N;$!ba;s/\n//g;s/\s//g;s/^.*<name>\(.*\)<\/name>.*$/\1/' ${m})
  ver=$(sed ':a;N;$!ba;s/\n//g;s/\s//g;s/^.*<version>\(.*\)<\/version>.*$/\1/' ${m})

  echo "Package: ${pkg} ${ver}-${rev} (at ${dir}) for ${ros_distro}"

  if [ -z ${ver_meta_pkg} ]; then
    ver_meta_pkg=${ver}
  fi
  if [ ${ver_meta_pkg} != ${ver} ]; then
    echo "Version inconsistency found!" >&2
    exit 1
  fi
  packages="${packages} ${pkg}"
done

echo
echo "=============================="
echo "Preparing ${ver_meta_pkg}"
echo

# Check local and remote version tag

if !git rev-parse ${ver_meta_pkg} >/dev/null 2>/dev/null; then
  echo "Release tag doesn't exist!" >&2
  exit 1
fi

if !(git ls-remote origin ${ver_meta_pkg} | grep "${ver_meta_pkg}" > /dev/null); then
  echo "Release tag is not yet pushed."
  read -p "Push now (y/n)? " answer
  case ${answer:0:1} in
    y | Y)
      echo "Pushing to source repository origin: ${ver_meta_pkg}"
      git push origin ${ver_meta_pkg}
      ;;
    *)
      git checkout ${base_branch}
      echo "Aborted"
      exit 1
      ;;
  esac
fi

# Generate releases

push_targets=
for m in ${manifests}; do
  dir=$(dirname ${m})
  pkg=$(sed ':a;N;$!ba;s/\n//g;s/\s//g;s/^.*<name>\(.*\)<\/name>.*$/\1/' ${m})
  branch=releasing/${ros_distro}/${pkg}/${ver_meta_pkg}-${rev}
  tag=release/${ros_distro}/${pkg}/${ver_meta_pkg}-${rev}

  git checkout ${ver_meta_pkg} 2>/dev/null
  git checkout --orphan ${branch}

  # Exclude workflow files to avoid requiring 'workflow' scope token
  rm -rf .github/workflows || true

  if [ ${dir} != "." ]; then
    echo "Extracting sub-directory"
    tmpdir=$(mktemp -d)
    cp -r ${dir}/* ${tmpdir}/
    rm -rf *
    mv ${tmpdir}/* ./
    rm -rf ${tmpdir}
  fi

  git tag -d ${tag} || true

  git add .
  git commit -m "Release ${pkg} ${ver_meta_pkg}-${rev} for ${ros_distro}" --allow-empty
  git tag -a -m "${tag}" ${tag}

  git checkout ${base_branch}
  git branch -D ${branch}

  push_targets="${push_targets} ${tag}"
done

echo
echo "=============================="
echo "Create release:"
echo "${push_targets}" | xargs -n1 echo | sed "s/^/- /"
echo

read -p "Push to ${release_repo} (y/n/s)? " answer
case ${answer:0:1} in
  y | Y)
    echo "Pushing to release repository ${release_repo}: ${push_targets}"
    git push ${release_repo} ${push_targets}
    ;;
  s | S)
    echo "Skipped"
    ;;
  *)
    echo "Aborted"
    exit 1
    ;;
esac

echo
echo "=============================="
echo "Preparing rosdistro update:"
echo

rosdistro_tmp=$(mktemp -d)
trap "{ rm -rf ${rosdistro_tmp}; }" EXIT

git clone --depth=1 -b ${rosdistro_repo_branch} ${rosdistro_repo} ${rosdistro_tmp}
git -C ${rosdistro_tmp} remote add fork ${rosdistro_push_repo}

ROS_DISTRO=${ros_distro} \
  SOURCE_REPO_URL=${source_repo} \
  SOURCE_BRANCH=${base_branch} \
  RELEASE_REPO_URL=${release_repo} \
  PACKAGES=${packages} \
  python3 $(dirname $0)/update-distributions.py \
  ${rosdistro_tmp}/${ros_distro}/distribution.yaml \
  ${meta_package} ${ver_meta_pkg} ${rev}

release_branch_name=release-${ros_distro}-${meta_package}-${ver_meta_pkg}-${rev}
git -C ${rosdistro_tmp} diff ${rosdistro_repo_branch}
git -C ${rosdistro_tmp} checkout -b ${release_branch_name}
git -C ${rosdistro_tmp} add ${rosdistro_tmp}/${ros_distro}/distribution.yaml
git -C ${rosdistro_tmp} commit -m "Release ${meta_package} ${ver_meta_pkg}-${rev}"

echo
echo "=============================="
echo "Release: ${ver_meta_pkg}-${rev}"
echo

pr_request_body=$(
  cat <<EOS
{
  "title": "Release ${meta_package} ${ver_meta_pkg}-${rev} to ${ros_distro}",
  "body": "",
  "head": "${rosdistro_push_user}:${release_branch_name}",
  "base": "${rosdistro_repo_branch}"
}
EOS
)

echo "PR: ${pr_request_body}"
echo

read -p "Push ${release_branch_name} to ${rosdistro_push_repo} and open a pull request (y/n/s)? " answer
case ${answer:0:1} in
  y | Y) ;;
  s | S)
    echo "Skipped"
    exit 0
    ;;
  *)
    echo "Aborted"
    exit 1
    ;;
esac

echo "Pushing to rosdistro1 fork: ${release_branch_name}"
git -C ${rosdistro_tmp} push fork ${release_branch_name}

sleep 1

curl https://api.github.com/repos/${rosdistro_repo_slug}/pulls -d "${pr_request_body}" -XPOST -n \
  || (
    echo "Failed to open a pull request. GitHub personal access token for api.github.com is not set up." >&2
    echo "Please manually open the pull request." >%2
    exit 1
  )
