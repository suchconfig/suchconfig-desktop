#!/bin/bash

set -e

echo "🔧 Setting up Elixir with asdf..."

if ! command -v asdf &> /dev/null; then
    echo "❌ asdf is not installed. Installing asdf..."
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install asdf
        else
            echo "Please install Homebrew first: https://brew.sh"
            echo "Then run: brew install asdf"
            exit 1
        fi
    else
        echo "Please install asdf manually: https://asdf-vm.com/guide/getting-started.html"
        exit 1
    fi
    
    echo "✅ asdf installed"
    
    echo "Adding asdf to shell configuration..."
    if [[ "$SHELL" == *"zsh"* ]]; then
        echo -e "\n. $(brew --prefix asdf)/libexec/asdf.sh" >> ~/.zshrc
        source ~/.zshrc
    fi
fi

echo "✅ asdf is installed"

echo "Adding Elixir plugin..."
asdf plugin add elixir || echo "Elixir plugin already exists"

echo "Adding Erlang plugin (required for Elixir)..."
asdf plugin add erlang || echo "Erlang plugin already exists"

echo "Installing Erlang OTP 27..."
asdf install erlang 27.0.1

echo "Installing Elixir 1.18.4..."
asdf install elixir 1.18.4-otp-27

cd phoenix-app

echo "Setting local Elixir version for this project..."
asdf local elixir 1.18.4-otp-27
asdf local erlang 27.0.1

cd ..

echo ""
echo "✅ Elixir setup complete!"
echo ""
echo "To verify installation, run:"
echo "  cd phoenix-app"
echo "  mix --version"
echo "  elixir --version"

