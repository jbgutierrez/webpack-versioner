build:
	@./node_modules/.bin/coffee -b -o lib src/*.coffee
	@echo '#!/usr/bin/env node' | cat - lib/cli.js > lib/cli

test: build
	@NODE_ENV=test ./node_modules/.bin/mocha --compilers coffee:coffee-script

.PHONY: test
