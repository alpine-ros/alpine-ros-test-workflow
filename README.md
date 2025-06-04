# alpine-ros/alpine-ros-ci-workflows

GitHub Action workflow to test ROS package using Alpine ROS

## Usage

```yaml
name: ci
on:
  pull_request:
  push:
    branches:
      - main

permissions:
  contents: read        # Checkout the source code
  packages: read        # Pull Alpine ROS builder image
  issues: write         # Post/Hide bot comment
  pull-requests: write  # Post/Hide bot comment

jobs:
  test:
    uses: alpine-ros/alpine-ros-ci-workflows/.github/workflows/ros1.yaml@main
    with:
      enable-bot-comment: true
    secrets:
      bot-comment-token: ${{ secrets.GITHUB_TOKEN }}
```
