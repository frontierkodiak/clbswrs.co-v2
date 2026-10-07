.DEFAULT_GOAL := check

JEKYLL_BUILD_ARGS ?=

.PHONY: setup build serve test check clean

setup:
	bundle install

build:
	JEKYLL_ENV=production bundle exec jekyll build --strict_front_matter --trace $(JEKYLL_BUILD_ARGS)

serve:
	bundle exec jekyll serve --livereload

test:
	ruby tools/transcripts/test/transcripts_test.rb

check: test build
	bundle exec htmlproofer ./_site --disable-external --no-enforce-https
	test -f _site/index.html
	test -f _site/404.html
	test "$$(tr -d '\r\n' < _site/CNAME)" = "clbswrs.co"

clean:
	bundle exec jekyll clean
