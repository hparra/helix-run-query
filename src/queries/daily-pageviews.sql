--- description: Get daily page views for a site according to Helix RUM data
--- Authorization: none
--- Access-Control-Allow-Origin: *
--- limit: 30
--- offset: 0
--- url: 
--- granularity: 1
DECLARE results NUMERIC;
CREATE OR REPLACE PROCEDURE helix_rum.UPDATE_PAGEVIEWS(ingranularity INT64, inlimit INT64, inoffset INT64, inurl STRING, OUT results NUMERIC)
BEGIN
    CREATE TEMP TABLE PAGEVIEWS(year INT64, month INT64, day INT64, time STRING, url INT64, pageviews NUMERIC)
    AS
        WITH current_data AS (
        SELECT CASE ingranularity
                WHEN 7 THEN TIMESTAMP_TRUNC(TIMESTAMP_MILLIS(CAST(time AS INT64)), ISOWEEK)
                WHEN 30 THEN TIMESTAMP_TRUNC(TIMESTAMP_MILLIS(CAST(time AS INT64)), MONTH)
                WHEN 90 THEN TIMESTAMP_TRUNC(TIMESTAMP_MILLIS(CAST(time AS INT64)), QUARTER)
                WHEN 365 THEN TIMESTAMP_TRUNC(TIMESTAMP_MILLIS(CAST(time AS INT64)), YEAR)
                ELSE TIMESTAMP_TRUNC(TIMESTAMP_MILLIS(CAST(time AS INT64)), DAY)
            END AS date,
            * 
        FROM `helix-225321.helix_rum.rum*`
        WHERE 
            # use date partitioning to reduce query size
            _TABLE_SUFFIX <= CONCAT(CAST(EXTRACT(YEAR FROM CURRENT_TIMESTAMP()) AS String), LPAD(CAST(EXTRACT(MONTH FROM CURRENT_TIMESTAMP()) AS String), 2, "0")) AND
            _TABLE_SUFFIX >= CONCAT(CAST(EXTRACT(YEAR FROM TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL (CAST(inlimit AS INT64) * CAST(ingranularity AS INT64)) DAY)) AS String), LPAD(CAST(EXTRACT(MONTH FROM TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL CAST(inlimit AS INT64) DAY)) AS String), 2, "0")) AND
            CAST(time AS STRING) > CAST(UNIX_MICROS(TIMESTAMP_SUB(TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), DAY), INTERVAL SAFE_ADD((CAST(inlimit AS INT64) * CAST(ingranularity AS INT64)), -1) DAY)) AS STRING) AND
            CAST(time AS STRING) < CAST(UNIX_MICROS(TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL SAFE_ADD((CAST(inoffset AS INT64) * CAST(ingranularity AS INT64)), 0) DAY)) AS STRING) AND
            url LIKE CONCAT("https://", inurl, "%")
        ),
        pageviews_by_id AS (
            SELECT 
                MAX(date) AS date, 
                MAX(url) AS url,
                id,
                MAX(weight) AS weight
            FROM current_data 
            GROUP BY id),
        dailydata AS (
        SELECT
            EXTRACT(YEAR FROM date) AS year,
            EXTRACT(MONTH FROM date) AS month,
            EXTRACT(DAY FROM date) AS day,
            STRING(date) AS time,
            COUNT(url) AS urls,
            SUM(weight) AS pageviews,
        FROM pageviews_by_id
        GROUP BY date
        ORDER BY date DESC),
        basicdates AS (
            SELECT alldates FROM UNNEST(generate_timestamp_array((SELECT MIN(date) FROM pageviews_by_id),(SELECT MAX(date) FROM pageviews_by_id), INTERVAL 1 DAY)) AS alldates
        ),
        dates AS (
            SELECT CASE ingranularity 
                WHEN 7 THEN TIMESTAMP_TRUNC(alldates, ISOWEEK) 
                WHEN 30 THEN TIMESTAMP_TRUNC(alldates, MONTH) 
                WHEN 90 THEN TIMESTAMP_TRUNC(alldates, QUARTER) 
                WHEN 365 THEN TIMESTAMP_TRUNC(alldates, YEAR) 
                ELSE TIMESTAMP_TRUNC(alldates, DAY) 
            END AS alldates FROM basicdates
            GROUP BY alldates
        ),
        finaldata AS (
        SELECT 
            EXTRACT(YEAR FROM dates.alldates) AS year,
            EXTRACT(MONTH FROM dates.alldates) AS month,
            EXTRACT(DAY FROM dates.alldates) AS day,
            STRING(dates.alldates) AS time, 
            COALESCE(dailydata.urls, 0) AS url,
            COALESCE(dailydata.pageviews, 0) AS pageviews
        FROM dates 
            FULL JOIN dailydata 
            ON STRING(dates.alldates) = dailydata.time
        ORDER BY dates.alldates DESC
        )
        SELECT * FROM finaldata ORDER BY time DESC;
    SET results = (SELECT SUM(pageviews) FROM (SELECT * FROM PAGEVIEWS));
END;
IF (CAST(@granularity AS STRING) = "auto") THEN
    CALL helix_rum.UPDATE_PAGEVIEWS(1, CAST(@limit AS INT64), CAST(@offset AS INT64), @url, results);
    IF (results > (CAST(@limit AS INT64) * 200)) THEN
        # we have enough results, use the daily granularity
        SELECT * FROM PAGEVIEWS;
    ELSE
        # we don't have enough results, zoom out
        DROP TABLE PAGEVIEWS;
        CALL helix_rum.UPDATE_PAGEVIEWS(7, CAST(@limit AS INT64), CAST(@offset AS INT64), @url, results);
        IF (results > (CAST(@limit AS INT64) * 200)) THEN
            # we have enough results, use the weekly granularity
            SELECT * FROM PAGEVIEWS;
        ELSE
            # we don't have enough results, zoom out to monthly and stop
            DROP TABLE PAGEVIEWS;
            CALL helix_rum.UPDATE_PAGEVIEWS(30, CAST(@limit AS INT64), CAST(@offset AS INT64), @url, results);
            SELECT * FROM PAGEVIEWS;
        END IF;
    END IF;
ELSE
    CALL helix_rum.UPDATE_PAGEVIEWS(CAST(@granularity AS INT64), CAST(@limit AS INT64), CAST(@offset AS INT64), @url, results);
    SELECT * FROM PAGEVIEWS;
END IF;
