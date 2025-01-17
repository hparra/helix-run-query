--- description: Guess hostname from owner/repo/ref and vice versa
--- Authorization: none
--- limit: 10
--- interval: 30
--- domain: -
--- owner: -
--- repo: -
--- ref: -
WITH data AS (
SELECT 
    COUNT(time_start_usec) AS requests,
    REGEXP_EXTRACT(req_http_Referer, r"https://([^/]+)", 1) AS host, 
    req_http_X_Owner AS owner, 
    req_http_X_Repo AS repo,
    req_http_X_Ref AS ref,
FROM `helix-225321.helix_logging_7TvULgs0Xnls4q3R8tawdg.requests*` 
WHERE 
    # use date partitioning to reduce query size
    _TABLE_SUFFIX <= CONCAT(CAST(EXTRACT(YEAR FROM CURRENT_TIMESTAMP()) AS String), LPAD(CAST(EXTRACT(MONTH FROM CURRENT_TIMESTAMP()) AS String), 2, "0")) AND
    _TABLE_SUFFIX >= CONCAT(CAST(EXTRACT(YEAR FROM TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL CAST(@interval AS INT64) DAY)) AS String), LPAD(CAST(EXTRACT(MONTH FROM TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)) AS String), 2, "0")) AND
    CAST(time_start_usec AS STRING) > CAST(UNIX_MICROS(TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL CAST(@interval AS INT64) DAY)) AS STRING) AND
    CAST(time_start_usec AS STRING) < CAST(UNIX_MICROS(TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 0 DAY)) AS STRING) AND
    REGEXP_CONTAINS(req_http_Referer, r"https://[^/]+/.*")
    AND REGEXP_EXTRACT(req_http_Referer, r"https://([^/]+)", 1) NOT LIKE "%.hlx3.page"
    AND REGEXP_EXTRACT(req_http_Referer, r"https://([^/]+)", 1) NOT LIKE "%.hlx.live"
GROUP BY 
    req_http_X_Repo, 
    req_http_X_Owner, 
    req_http_X_Ref,
    host
ORDER BY requests DESC
)
SELECT * FROM data WHERE
    (owner = @owner OR @owner = "-") AND
    (repo = @repo OR @repo = "-") AND
    (ref = @ref OR @ref = "-") AND
    (host = @domain OR @domain = "-")
LIMIT CAST(@limit AS INT64)