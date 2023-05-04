local client = {
	base = "https://leetcode.cn",
	cookie = nil,
	prefer_lang = nil,
}

client.request = function(self, url, opts)
	local method = opts.method or "GET"
	local data = opts.data

	local headers = {}
	headers["Content-Type"] = "application/json"
	headers["Origin"] = self.base
	headers["Referer"] = self.base
	headers["Cookie"] = self.cookie

	local cmd = [[curl --silent --write-out "%{http_code}"]]
	cmd = cmd .. string.format([[ --request %s --location '%s']], method, url)
	for k, v in pairs(headers) do
		cmd = cmd .. string.format([[ --header '%s: %s']], k, v)
	end
	if data then
		cmd = cmd .. string.format([[ --data '%s']], data)
	end

	local result = vim.fn.system(cmd)
	-- if vim.v.shell_error == 0 then
	-- 	return result
	-- end
	local code = string.sub(result, string.len(result) - 2)
	if code == "200" then
		local content = string.sub(result, 0, string.len(result) - 3)
		return vim.json.decode(content)
	else
		vim.print("status code: " .. code)
	end
end

client.graphqlreq = function(self, data)
	local url = "https://leetcode.cn/graphql"
	local resp = self:request(url, {
		method = "POST",
		data = data,
	})
	return resp
end

client.user = function(self)
	local data = [[{
		"query": "query globalData { userStatus { isSignedIn isPremium username realName avatar userSlug isAdmin checkedInToday useTranslation premiumExpiredAt isTranslator isSuperuser isPhoneVerified isVerified } jobsMyCompany { nameSlug } } ",
		"variables": {},
		"operationName": "globalData"
	}]]
	local res = self:graphqlreq(data)
	-- {
	--   data = {
	--     jobsMyCompany = vim.NIL,
	--     userStatus = {
	--       avatar = "https://assets.leetcode.cn/aliyun-lc-upload/default_avatar.png",
	--       checkedInToday = true,
	--       isAdmin = false,
	--       isPhoneVerified = true,
	--       isPremium = false,
	--       isSignedIn = true,
	--       isSuperuser = false,
	--       isTranslator = false,
	--       isVerified = true,
	--       premiumExpiredAt = 946684800000,
	--       realName = "allenLiu",
	--       useTranslation = true,
	--       userSlug = "gh-liu",
	--       username = "gh-liu"
	--     }
	--   }
	-- }
	if res then
		local user_info = {
			name = res.data.userStatus.username,
			slug = res.data.userStatus.userSlug,
			realname = res.data.userStatus.realName,
		}
		return user_info
	end
end

client.session = function(self)
	local data = [[{
		"query": "query userSessions {sessionUserSessions {sessions {id isActive name}}}",
		"variables": {},
		"operationName": "userSessions"
	}]]
	local resp = self:graphqlreq(data)
	if resp then
		for i, v in ipairs(resp.data.sessionUserSessions.sessions) do
			if v.isActive then
				return {
					name = v.name,
					id = v.id,
				}
			end
		end
	end
end

client.status = function(self, slug)
	local data = string.format(
		[[{
		"query": "query userSessionProgress($userSlug: String!) { userProfileUserQuestionSubmitStats(userSlug: $userSlug) { acSubmissionNum { difficulty count } totalSubmissionNum { difficulty count } } userProfileUserQuestionProgress(userSlug: $userSlug) { numAcceptedQuestions { difficulty count } numFailedQuestions { difficulty count } numUntouchedQuestions { difficulty count } } } ",
		"variables": {
			"userSlug": "%s"
		},
		"operationName": "userSessionProgress"
	}]],
		slug
	)
	local resp = self:graphqlreq(data)
	if resp then
		local questions_raw = resp.data.userProfileUserQuestionProgress
		local submissions_raw = resp.data.userProfileUserQuestionSubmitStats
		local parse = function(data)
			local result = {}
			for _, v in ipairs(data) do
				result[string.lower(v.difficulty)] = v.count
			end
			return result
		end

		local questions = {
			accepted = parse(questions_raw.numAcceptedQuestions),
			failed = parse(questions_raw.numFailedQuestions),
			untouched = parse(questions_raw.numUntouchedQuestions),
		}
		local submissions = {
			accepted = parse(submissions_raw.acSubmissionNum),
			total = parse(submissions_raw.totalSubmissionNum),
		}

		return { questions = questions, submissions = submissions }
	end
end

client.problemset = function(self)
	local data = string.format(
		[[{
		"query": "query problemsetQuestionList($categorySlug: String, $limit: Int, $skip: Int, $filters: QuestionListFilterInput) { problemsetQuestionList( categorySlug: $categorySlug limit: $limit skip: $skip filters: $filters ) { hasMore total questions { acRate difficulty freqBar frontendQuestionId isFavor paidOnly solutionNum status title titleCn titleSlug topicTags { name nameTranslated id slug } extra { hasVideoSolution topCompanyTags { imgUrl slug numSubscribed } } } }} ",
		"variables": {
			"categorySlug": "",
			"skip": 0,
			"limit": 5000,
			"filters": {}
		},
		"operationName": "problemsetQuestionList"
	}]],
		""
	)

	local resp = self:graphqlreq(data)
	if resp then
		local problemset = {}
		for i, v in ipairs(resp.data.problemsetQuestionList.questions) do
			table.insert(problemset, {
				id = v.frontendQuestionId,
				title = v.title,
				title_cn = v.titleCn,
				slug = v.titleSlug,
				status = v.status, -- TRIED, NOT_STARTED, AC
				difficulty = string.lower(v.difficulty),
			})
		end

		return problemset
	end
end

client.today = function(self)
	local data = [[{
		"operationName": "questionOfToday",
		"variables": {},
		"query": "query questionOfToday { todayRecord {  question {  titleSlug  __typename  }  __typename } } "
	}]]

	local resp = self:graphqlreq(data)
	if resp then
		return { slug = resp.data.todayRecord[1].question.titleSlug }
	end
end

client.detail = function(self, slug)
	local data = string.format(
		[[{
		"operationName": "getQuestionDetail",
		"variables": {"titleSlug": "%s"},
		"query": "query getQuestionDetail($titleSlug: String!) {\n question(titleSlug: $titleSlug) {\n content\n stats\n codeDefinition\n sampleTestCase\n exampleTestcases\n enableRunCode\n metaData\n translatedContent\n }\n }\n"
	}]],
		slug
	)

	local resp = self:graphqlreq(data)
	if resp then
		local result = {}

		local q = resp.data.question
		local code_definitions = vim.json.decode(q.codeDefinition)
		if code_definitions then
			for i, v in ipairs(code_definitions) do
				if v.value == self.prefer_lang then
					result["code_definition"] = v.defaultCode
					result["lang"] = self.prefer_lang
				end
			end
		end
		result["test_cases"] = q.exampleTestcases
		result["content"] = q.content
		result["content_cn"] = q.translatedContent

		return result
	end
end

client.data = function(self, slug)
	local data = string.format(
		[[{
		"operationName": "questionData",
		"variables": {
			"titleSlug": "%s"
		},
		"query": "query questionData($titleSlug: String!) { question(titleSlug: $titleSlug) { questionId questionFrontendId categoryTitle boundTopicId title titleSlug content translatedTitle translatedContent isPaidOnly difficulty likes dislikes isLiked similarQuestions contributors { username profileUrl avatarUrl __typename } langToValidPlayground topicTags { name slug translatedName __typename } companyTagStats codeSnippets { lang langSlug code __typename } stats hints solution { id canSeeDetail __typename } status sampleTestCase metaData judgerAvailable judgeType mysqlSchemas enableRunCode envInfo book { id bookName pressName source shortDescription fullDescription bookImgUrl pressImgUrl productUrl __typename } isSubscribed isDailyQuestion dailyRecordStatus editorType ugcQuestionId style exampleTestcases jsonExampleTestcases __typename }}"
	}]],
		slug
	)

	local resp = self:graphqlreq(data)
	if resp then
		local result = {}

		local q = resp.data.question
		result["id"] = q.questionId
		result["title"] = q.title
		result["title_cn"] = q.translatedTitle
		result["slug"] = q.titleSlug
		result["content"] = q.content
		result["content_cn"] = q.translatedContent
		result["test_cases"] = q.exampleTestcases

		if q.codeSnippets then
			for _, v in ipairs(q.codeSnippets) do
				if v.langSlug == self.prefer_lang then
					result["code_definition"] = v.code
					result["lang"] = self.prefer_lang
				end
			end
		end

		return result
	end
end

client.interpret = function(self, args)
	local slug = args.slug
	local name = args.title
	local question_id = args.id
	local test_cases = args.test_cases
	local code = args.code_definition
	local lang = args.lang

	local data = vim.json.encode({
		name = name,
		question_id = question_id,
		data_input = test_cases,
		typed_code = code,
		lang = lang,
	})

	local url = string.format([[%s/problems/%s/interpret_solution/]], self.base, slug)
	local resp = self:request(url, {
		method = "POST",
		data = data,
	})
	if resp then
		return { id = resp.interpret_id }
	end
end

client.submit = function(self, args)
	local slug = args.slug
	local name = args.title
	local question_id = args.id

	local typed_code = args.code_definition
	local lang = args.lang

	local url = string.format([[%s/problems/%s/submit/]], self.base, slug)
	local resp = self:request(url, {
		method = "POST",
		data = vim.json.encode({
			question_id = question_id,
			lang = lang,
			typed_code = typed_code,
			test_mode = false,
			test_judger = "",
			questionSlug = slug,
		}),
	})
	if resp then
		return { id = resp.submission_id }
	end
end

client.check = function(self, id)
	local url = string.format([[%s/submissions/detail/%s/check/]], self.base, id)
	local resp = self:request(url, {})
	if resp then
		local result = {
			state = resp.state, -- PENDING, STARTED, SUCCESS
		}
		if result.state == "SUCCESS" then
			vim.print(result.status_msg)
			if result.run_success then
				-- {
				--     "status_code": 10,
				--     "lang": "golang",
				--     "run_success": true,
				--     "status_runtime": "0 ms",
				--     "memory": 1792000,
				--     "code_answer": [
				--         "1"
				--     ],
				--     "code_output": [],
				--     "std_output_list": [
				--         "",
				--         ""
				--     ],
				--     "elapsed_time": 114,
				--     "task_finish_time": 1683364162713,
				--     "task_name": "judger.runcodetask.RunCode",
				--     "expected_status_code": 10,
				--     "expected_lang": "python3",
				--     "expected_run_success": true,
				--     "expected_status_runtime": "60",
				--     "expected_memory": 16208000,
				--     "expected_code_answer": [
				--         "1"
				--     ],
				--     "expected_code_output": [],
				--     "expected_std_output_list": [
				--         "",
				--         ""
				--     ],
				--     "expected_elapsed_time": 153,
				--     "expected_task_finish_time": 1683362606158,
				--     "expected_task_name": "judger.interprettask.Interpret",
				--     "correct_answer": true,
				--     "compare_result": "1",
				--     "status_msg": "Accepted",
				--     "state": "SUCCESS",
				--     "fast_submit": false,
				--     "total_correct": 1,
				--     "total_testcases": 1,
				--     "submission_id": "runcode_1683364161.3687892_0mLEaWJth2",
				--     "runtime_percentile": null,
				--     "status_memory": "1.8 MB",
				--     "memory_percentile": null,
				--     "pretty_lang": "Go"
				-- }
			else
				-- {
				--     "status_code": 20,
				--     "lang": "golang",
				--     "run_success": false,
				--     "compile_error": "Line 3: Char 1: missing return (solution.go)",
				--     "full_compile_error": "Line 3: Char 1: missing return (solution.go)",
				--     "status_runtime": "N/A",
				--     "memory": 0,
				--     "code_answer": [],
				--     "code_output": [],
				--     "std_output_list": [
				--         ""
				--     ],
				--     "task_finish_time": 1683363830504,
				--     "elapsed_time": 0,
				--     "task_name": "judger.runcodetask.RunCode",
				--     "status_msg": "Compile Error",
				--     "state": "SUCCESS",
				--     "fast_submit": false,
				--     "total_correct": null,
				--     "total_testcases": null,
				--     "submission_id": "runcode_1683363829.1446395_EfgfLpdObK",
				--     "runtime_percentile": null,
				--     "status_memory": "N/A",
				--     "memory_percentile": null,
				--     "pretty_lang": "Go"
				-- }
				vim.print(result.compile_error)
			end
		end

		return result
	end
end

return client
