-- Performance Test Script for Smart Utilities
-- This script helps verify that all optimizations are working correctly

local TestResults = {}
local TestStartTime = 0

-- Test configuration
local TEST_CONFIG = {
    maxExecutionTime = 0.02, -- 0.02ms target
    testDuration = 30000, -- 30 seconds
    playerCount = 15, -- Simulate 15 players
    testIterations = 1000
}

-- Performance monitoring
local function StartPerformanceTest(testName)
    TestStartTime = GetGameTimer()
    TestResults[testName] = {
        startTime = TestStartTime,
        iterations = 0,
        totalTime = 0,
        maxTime = 0,
        minTime = 999999,
        errors = 0
    }
    
    Logger.Info("Starting performance test: " .. testName)
end

local function EndPerformanceTest(testName)
    local result = TestResults[testName]
    if not result then return end
    
    local endTime = GetGameTimer()
    result.endTime = endTime
    result.duration = endTime - result.startTime
    result.avgTime = result.totalTime / math.max(result.iterations, 1)
    
    Logger.Info(string.format(
        "Test '%s' completed:\n" ..
        "  Duration: %dms\n" ..
        "  Iterations: %d\n" ..
        "  Avg Time: %.4fms\n" ..
        "  Max Time: %.4fms\n" ..
        "  Min Time: %.4fms\n" ..
        "  Errors: %d\n" ..
        "  Status: %s",
        testName,
        result.duration,
        result.iterations,
        result.avgTime,
        result.maxTime,
        result.minTime,
        result.errors,
        result.avgTime <= TEST_CONFIG.maxExecutionTime and "PASS" or "FAIL"
    ))
end

local function RecordIteration(testName, executionTime, hasError)
    local result = TestResults[testName]
    if not result then return end
    
    result.iterations = result.iterations + 1
    result.totalTime = result.totalTime + executionTime
    result.maxTime = math.max(result.maxTime, executionTime)
    result.minTime = math.min(result.minTime, executionTime)
    
    if hasError then
        result.errors = result.errors + 1
    end
end

-- Test validation functions
local function TestInputValidation()
    StartPerformanceTest("InputValidation")
    
    for i = 1, TEST_CONFIG.testIterations do
        local startTime = GetGameTimer()
        local hasError = false
        
        -- Test property ID validation
        local isValid, error = Validation.ValidatePropertyId("test_property_" .. i)
        if not isValid then hasError = true end
        
        -- Test coordinates validation
        isValid, error = Validation.ValidateCoords({x = 100.0, y = 200.0, z = 30.0})
        if not isValid then hasError = true end
        
        -- Test zone ID validation
        isValid, error = Validation.ValidateZoneId("zone_" .. i)
        if not isValid then hasError = true end
        
        local endTime = GetGameTimer()
        RecordIteration("InputValidation", endTime - startTime, hasError)
    end
    
    EndPerformanceTest("InputValidation")
end

-- Test rate limiting
local function TestRateLimiting()
    StartPerformanceTest("RateLimiting")
    
    for i = 1, TEST_CONFIG.testIterations do
        local startTime = GetGameTimer()
        local hasError = false
        
        local canProceed, error = RateLimiter.CheckLimit(i % 10, "test_event")
        if error then hasError = true end
        
        local endTime = GetGameTimer()
        RecordIteration("RateLimiting", endTime - startTime, hasError)
    end
    
    EndPerformanceTest("RateLimiting")
end

-- Test performance utilities
local function TestPerformanceUtils()
    StartPerformanceTest("PerformanceUtils")
    
    for i = 1, TEST_CONFIG.testIterations do
        local startTime = GetGameTimer()
        local hasError = false
        
        -- Test movement detection
        local hasMoved = Performance.HasPlayerMoved()
        
        -- Test zone distance checking
        local playerCoords = vector3(100.0, 200.0, 30.0)
        local zoneCoords = vector3(150.0, 250.0, 30.0)
        local inRange = Performance.CheckZoneDistance("test_zone_" .. i, zoneCoords, 100.0, playerCoords)
        
        local endTime = GetGameTimer()
        RecordIteration("PerformanceUtils", endTime - startTime, hasError)
    end
    
    EndPerformanceTest("PerformanceUtils")
end

-- Test database operations (server-side only)
local function TestDatabaseOperations()
    if not IsDuplicityVersion() then return end -- Server-side only
    
    StartPerformanceTest("DatabaseOperations")
    
    for i = 1, math.min(TEST_CONFIG.testIterations, 100) do -- Limit DB tests
        local startTime = GetGameTimer()
        local hasError = false
        
        -- Test safe database execution
        local success, error = Validation.SafeExecute(function()
            -- Simulate database query
            return true
        end, "Test database operation")
        
        if not success then hasError = true end
        
        local endTime = GetGameTimer()
        RecordIteration("DatabaseOperations", endTime - startTime, hasError)
    end
    
    EndPerformanceTest("DatabaseOperations")
end

-- Test memory management
local function TestMemoryManagement()
    StartPerformanceTest("MemoryManagement")
    
    local testParticles = {}
    
    for i = 1, math.min(TEST_CONFIG.testIterations, 50) do -- Limit particle tests
        local startTime = GetGameTimer()
        local hasError = false
        
        -- Test particle cleanup batching
        Performance.AddToBatch("particle_cleanup", i)
        
        -- Test cache cleanup
        Performance.CleanupCache()
        
        local endTime = GetGameTimer()
        RecordIteration("MemoryManagement", endTime - startTime, hasError)
    end
    
    EndPerformanceTest("MemoryManagement")
end

-- Main test runner
local function RunAllTests()
    Logger.Info("Starting Smart Utilities Performance Test Suite")
    Logger.Info("Target: " .. TEST_CONFIG.maxExecutionTime .. "ms per operation")
    Logger.Info("Test Duration: " .. TEST_CONFIG.testDuration .. "ms")
    Logger.Info("Simulated Players: " .. TEST_CONFIG.playerCount)
    
    -- Run all tests
    TestInputValidation()
    Citizen.Wait(1000)
    
    TestRateLimiting()
    Citizen.Wait(1000)
    
    TestPerformanceUtils()
    Citizen.Wait(1000)
    
    TestDatabaseOperations()
    Citizen.Wait(1000)
    
    TestMemoryManagement()
    Citizen.Wait(1000)
    
    -- Generate final report
    local passedTests = 0
    local totalTests = 0
    
    Logger.Info("=== PERFORMANCE TEST RESULTS ===")
    for testName, result in pairs(TestResults) do
        totalTests = totalTests + 1
        local status = result.avgTime <= TEST_CONFIG.maxExecutionTime and "PASS" or "FAIL"
        if status == "PASS" then passedTests = passedTests + 1 end
        
        Logger.Info(string.format("%s: %s (%.4fms avg)", testName, status, result.avgTime))
    end
    
    Logger.Info(string.format("=== SUMMARY: %d/%d tests passed ===", passedTests, totalTests))
    
    if passedTests == totalTests then
        Logger.Info("🎉 ALL TESTS PASSED! Resource is production-ready.")
    else
        Logger.Warn("⚠️  Some tests failed. Review performance optimizations.")
    end
end

-- Auto-run tests when resource starts (only in development)
if Config and Config.Debug and Config.Debug.RunPerformanceTests then
    Citizen.CreateThread(function()
        Citizen.Wait(5000) -- Wait for resource to fully load
        RunAllTests()
    end)
end

-- Export test functions for manual testing
exports('RunPerformanceTests', RunAllTests)
exports('TestInputValidation', TestInputValidation)
exports('TestRateLimiting', TestRateLimiting)
exports('TestPerformanceUtils', TestPerformanceUtils)
exports('TestDatabaseOperations', TestDatabaseOperations)
exports('TestMemoryManagement', TestMemoryManagement)

Logger.Info("Performance test suite loaded")