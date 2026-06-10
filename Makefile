help:  ## Print this help
	@grep -E '^[a-zA-Z][a-zA-Z0-9_-]*:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'


docker:  ## Build claud docker image
	docker build -t mclaude:latest . --load


install:  ## Install mclaude script
	sudo install -pm755 mclaude /usr/local/bin/mclaude


shell:  ## Run shell inside container
	docker run -it --rm -v $(PWD):/src -e CLAUDE_WORKDIR=/src -e TZ=$$(cat /etc/timezone) -v /etc/localtime:/etc/localtime:ro -v $(HOME)/.gitconfig:/home/claude/.gitconfig -v $(HOME)/.mclaude/.claude:/home/claude/.claude mclaude bash


up:  ## Start the long-running container (needs .env; see docker-compose.yml)
	docker compose up -d


down:  ## Stop and remove the long-running container
	docker compose down

