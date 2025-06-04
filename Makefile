.PHONY: fmt
fmt:
	# Install shfmt by `go install mvdan.cc/sh/v3/cmd/shfmt@latest`
	shfmt -i 2 -ci -bn -l -w .
