
#!/usr/bin/env bash

echo "go path $GOPATH"
set -e
echo "" > coverage.txt
go mod download
for d in $(go list ./... | grep -v vendor); do
    go test -race -coverprofile=profile.out -covermode=atomic "$d"
    if [ -f profile.out ]; then
        cat profile.out >> coverage.txt
        rm profile.out
    fi
done
