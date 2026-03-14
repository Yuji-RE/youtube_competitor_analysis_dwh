VENV := source /home/yuji/data_analysis_projects/.venv/bin/activate
PSQL := docker exec -i youtube_dwh_db psql -U yuji -d youtube_dwh_db

db-up:
	docker compose up -d

db-down:
	docker compose down

pipeline:
	$(PSQL) \
		-f /sql/01_create_tables.sql \
		-f /sql/02_import_and_clean_self.sql \
		-f /sql/03_import_and_clean_competitor.sql \
		-f /sql/04_mart.sql \
		-f /sql/05_quality_checks.sql

collect:
	bash -c "$(VENV) && python3 src/python/collect_competitor.py"

.PHONY: db-up db-down pipeline collect
