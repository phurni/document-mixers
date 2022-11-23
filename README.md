# document-mixers

Here are scripts to convert, transform, generate, well **mix** markdown files to produce good looking documents.

## Prerequisites

You need a [ruby (>= 2)](https://ruby-lang.org) and a [node (>= 12)](https://nodejs.org).

## Installation

Follow the two steps procedure below.

**NOTE:** Windows users should rename the scripts with a `.ps1` extension so that they can be run directly from the PowerShell prompt.

### Dependencies

Run the `install-dependencies` script to install the ruby and node dependencies.

### Deploy

In order to be able to run the scripts from anywhere, run the `deploy-rake-task` script.

## Usage

The scripts are available as `rake` tasks, list them with:

```sh
rake -g -T
```

Or ask for the full description of a particular task:

```sh
rake -g -D document:generate:kramdown
```

Run one of them:

```sh
rake -g document:template:help
```
