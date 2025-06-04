# alpine-ros/alpine-ros-test-workflow

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
    uses: ./.github/workflows/ros1.yaml
    with:
      enable-bot-comment: true
    secrets:
      bot-comment-token: ${{ secrets.GITHUB_TOKEN }}
```
