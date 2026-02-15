--[[
  eval/stats.lua — Statistical aggregation

  Computes pass@k, confidence intervals, and descriptive statistics.
  Ported from agent-swarm's aggregator (Rust → Lua).
]]

local M = {}

-- ============================================================
-- Descriptive statistics
-- ============================================================

---@param values number[]
---@return table {n, mean, std_dev, min, max, median}
function M.describe(values)
  local n = #values
  if n == 0 then
    return { n = 0, mean = 0, std_dev = 0, min = 0, max = 0, median = 0 }
  end

  local sorted = {}
  for i, v in ipairs(values) do sorted[i] = v end
  table.sort(sorted)

  local sum = 0
  for _, v in ipairs(sorted) do sum = sum + v end
  local mean = sum / n

  local sq_sum = 0
  for _, v in ipairs(sorted) do
    sq_sum = sq_sum + (v - mean) ^ 2
  end
  local std_dev = n > 1 and math.sqrt(sq_sum / (n - 1)) or 0

  local median
  if n % 2 == 1 then
    median = sorted[math.ceil(n / 2)]
  else
    median = (sorted[n / 2] + sorted[n / 2 + 1]) / 2
  end

  return {
    n       = n,
    mean    = mean,
    std_dev = std_dev,
    min     = sorted[1],
    max     = sorted[n],
    median  = median,
  }
end

-- ============================================================
-- pass@k computation
--
-- Semantics: probability of at least 1 pass when drawing k results
-- from the full result pool without replacement.
-- Differs from OpenAI's pass@k (k independent trials on the same input).
-- ============================================================

--- log(C(n, k)) using sum of logs for numerical stability
local function log_comb(n, k)
  if k > n then return -math.huge end
  if k == 0 or k == n then return 0 end
  if k > n - k then k = n - k end
  local result = 0
  for i = 0, k - 1 do
    result = result + math.log(n - i) - math.log(i + 1)
  end
  return result
end

--- Compute pass@k: probability of at least one success in k tries.
--- Formula: 1 - C(n-c, k) / C(n, k)
---@param n number  total runs
---@param c number  successful runs
---@param k number  tries
---@return number
function M.pass_at_k(n, c, k)
  if n < k then return c > 0 and 1.0 or 0.0 end
  if c == 0 then return 0.0 end
  if c >= n then return 1.0 end

  -- C(n-c, k) / C(n, k) = probability of NO success in k tries
  local log_no_success = log_comb(n - c, k) - log_comb(n, k)

  -- Guard against numerical issues
  if log_no_success == -math.huge then return 1.0 end

  return 1.0 - math.exp(log_no_success)
end

-- ============================================================
-- 95% confidence interval
-- ============================================================

-- t-distribution critical values (two-tailed 95%, df → t)
local T_TABLE = {
  { 1, 12.706 }, { 2, 4.303 }, { 3, 3.182 }, { 4, 2.776 }, { 5, 2.571 },
  { 6, 2.447 }, { 7, 2.365 }, { 8, 2.306 }, { 9, 2.262 }, { 10, 2.228 },
  { 15, 2.131 }, { 20, 2.086 }, { 25, 2.060 }, { 30, 2.042 },
  { 40, 2.021 }, { 60, 2.000 }, { 80, 1.990 }, { 100, 1.984 }, { 120, 1.980 },
}

local function t_critical(df)
  if df <= 0 then return 1.96 end
  if df > 120 then return 1.96 end

  local prev = T_TABLE[1]
  for _, entry in ipairs(T_TABLE) do
    if entry[1] == df then return entry[2] end
    if entry[1] > df then
      -- Linear interpolation
      local frac = (df - prev[1]) / (entry[1] - prev[1])
      return prev[2] + frac * (entry[2] - prev[2])
    end
    prev = entry
  end
  return 1.96
end

--- Compute 95% confidence interval for the mean.
---@param stats table {n, mean, std_dev}
---@return number lower, number upper
function M.ci_95(stats)
  if stats.n < 2 then
    return stats.mean, stats.mean
  end
  local t = t_critical(stats.n - 1)
  local margin = t * stats.std_dev / math.sqrt(stats.n)
  -- Clamp to [0, 1] since scores are bounded
  local lower = math.max(0.0, stats.mean - margin)
  local upper = math.min(1.0, stats.mean + margin)
  return lower, upper
end

-- ============================================================
-- Aggregate eval results
-- ============================================================

---@param results table[]  CaseResult[] (from runner.run)
---@return table aggregated
function M.aggregate(results)
  local n = #results
  if n == 0 then
    return {
      total     = 0,
      passed    = 0,
      pass_rate = 0,
      pass_at_1 = 0,
      scores    = M.describe({}),
      ci_95     = { lower = 0, upper = 0 },
      by_tag    = {},
    }
  end

  local passed = 0
  local scores = {}
  local by_tag = {}

  for _, r in ipairs(results) do
    scores[#scores + 1] = r.score
    if r.passed then passed = passed + 1 end

    -- Accumulate by tag
    for _, tag in ipairs(r.case.tags) do
      if not by_tag[tag] then
        by_tag[tag] = { pass = 0, fail = 0, scores = {} }
      end
      by_tag[tag].scores[#by_tag[tag].scores + 1] = r.score
      if r.passed then
        by_tag[tag].pass = by_tag[tag].pass + 1
      else
        by_tag[tag].fail = by_tag[tag].fail + 1
      end
    end
  end

  local score_stats = M.describe(scores)
  local ci_lower, ci_upper = M.ci_95(score_stats)

  -- Finalize by_tag
  for tag, data in pairs(by_tag) do
    data.rate = data.pass / (data.pass + data.fail)
    data.stats = M.describe(data.scores)
    data.scores = nil  -- drop raw data
  end

  return {
    total      = n,
    passed     = passed,
    pass_rate  = passed / n,
    pass_at_1  = M.pass_at_k(n, passed, 1),
    pass_at_5  = n >= 5 and M.pass_at_k(n, passed, 5) or nil,
    pass_at_10 = n >= 10 and M.pass_at_k(n, passed, 10) or nil,
    scores     = score_stats,
    ci_95      = { lower = ci_lower, upper = ci_upper },
    by_tag     = by_tag,
  }
end

return M
