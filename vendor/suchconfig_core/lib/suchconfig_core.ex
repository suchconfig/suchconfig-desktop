defmodule SuchConfigCore do
  @moduledoc """
  SuchConfig Core - A comprehensive parsing library for multiple data formats.

  This library provides robust parsing capabilities for various data formats including
  JWT tokens, JSON, CSV, XML, and PDF documents. It serves as the shared foundation
  for all SuchConfig applications across web, desktop, CLI, and NPM platforms.

  ## Features

  ### JWT Token Parsing
  - Complete JWT decoding and validation
  - Security analysis and vulnerability detection
  - Bulk processing capabilities
  - Best practices recommendations

  ### Multi-Format Support
  - JSON parsing with validation
  - CSV parsing with delimiter detection
  - XML parsing with namespace support
  - PDF text extraction and metadata parsing

  ### Security & Validation
  - Comprehensive input validation
  - Security scoring algorithms
  - Vulnerability detection
  - Best practice recommendations

  ## Quick Start

      # Decode a JWT token
      {:ok, result} = SuchConfigCore.Parsers.JwtParser.decode_token(token)
      IO.inspect(result.security_score)

      # Process multiple tokens
      {:ok, results} = SuchConfigCore.Parsers.JwtParser.bulk_decode_tokens(tokens, "batch-001")
      IO.inspect(results.stats)

  ## Architecture

  The library is organized into several modules:

  - `SuchConfigCore.Parsers` - Core parsing functionality
  - `SuchConfigCore.Analyzers` - Security analysis and recommendations
  - `SuchConfigCore.Validators` - Input validation and format checking
  - `SuchConfigCore.Transformers` - Data format conversion utilities
  - `SuchConfigCore.Utils` - Common utility functions

  ## Security

  SuchConfig Core implements comprehensive security analysis for JWT tokens:

  - Algorithm validation (HS256, RS256, ES256)
  - Expiration verification
  - Vulnerability scanning
  - Security scoring (0-100)
  - Best practice recommendations

  ## Platform Support

  - **Web**: Direct dependency in Phoenix applications
  - **Desktop**: Embedded in Burrito binary for native performance
  - **CLI**: Core dependency for escript-based tools
  - **NPM**: Compiled to JavaScript via ElixirScript
  - **Hex**: Published package for Elixir developers

  ## License

  This project is licensed under the MIT License.
  """

  @version "0.1.1"

  @doc """
  Returns the current version of SuchConfig Core.
  """
  def version, do: @version

  @doc """
  Returns information about the library and its capabilities.
  """
  def info do
    %{
      name: "SuchConfig Core",
      version: @version,
      description: "A comprehensive parsing library for multiple data formats",
      parsers: [
        "JWT",
        "JSON (planned)",
        "CSV (planned)",
        "XML (planned)",
        "PDF (planned)"
      ],
      features: [
        "Security analysis",
        "Vulnerability detection",
        "Bulk processing",
        "Best practice recommendations"
      ],
      platforms: [
        "Web (Phoenix)",
        "Desktop (Tauri)",
        "CLI (escript)",
        "NPM (JavaScript)",
        "Hex (Elixir)"
      ]
    }
  end
end
