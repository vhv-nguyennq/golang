#!/bin/bash
# Setup script to add Go binaries to PATH permanently
# Run: source scripts/setup-path.sh

GOPATH_BIN="$(go env GOPATH)/bin"

# Check if already in PATH
if [[ ":$PATH:" != *":$GOPATH_BIN:"* ]]; then
    echo "Adding $GOPATH_BIN to PATH..."
    export PATH="$PATH:$GOPATH_BIN"
    
    # Add to bash profile for persistence
    if [ -f ~/.bashrc ]; then
        if ! grep -q "export PATH=.*$GOPATH_BIN" ~/.bashrc; then
            echo "" >> ~/.bashrc
            echo "# Go binaries (added by VHV setup)" >> ~/.bashrc
            echo "export PATH=\"\$PATH:$GOPATH_BIN\"" >> ~/.bashrc
            echo "Added to ~/.bashrc"
        fi
    fi
    
    if [ -f ~/.bash_profile ]; then
        if ! grep -q "export PATH=.*$GOPATH_BIN" ~/.bash_profile; then
            echo "" >> ~/.bash_profile
            echo "# Go binaries (added by VHV setup)" >> ~/.bash_profile
            echo "export PATH=\"\$PATH:$GOPATH_BIN\"" >> ~/.bash_profile
            echo "Added to ~/.bash_profile"
        fi
    fi
    
    echo "✅ PATH updated successfully!"
    echo "Current PATH includes: $GOPATH_BIN"
else
    echo "✅ $GOPATH_BIN already in PATH"
fi

# Verify protoc plugins
echo ""
echo "Checking protoc plugins..."
which protoc-gen-go >/dev/null 2>&1 && echo "✅ protoc-gen-go" || echo "❌ protoc-gen-go (run: go install google.golang.org/protobuf/cmd/protoc-gen-go@latest)"
which protoc-gen-go-grpc >/dev/null 2>&1 && echo "✅ protoc-gen-go-grpc" || echo "❌ protoc-gen-go-grpc (run: go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest)"
which protoc-gen-grpc-gateway >/dev/null 2>&1 && echo "✅ protoc-gen-grpc-gateway" || echo "❌ protoc-gen-grpc-gateway (run: go install github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-grpc-gateway@latest)"
which protoc-gen-openapiv2 >/dev/null 2>&1 && echo "✅ protoc-gen-openapiv2" || echo "❌ protoc-gen-openapiv2 (run: go install github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-openapiv2@latest)"
