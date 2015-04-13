build:
	@./node_modules/.bin/coffee -b -o lib src/*.coffee

add_shebang:
	@echo '#!/usr/bin/env node' | cat - lib/cli.js > lib/cli

test: build add_shebang
	@NODE_ENV=test ./node_modules/.bin/mocha --compilers coffee:coffee-script

.PHONY: test
