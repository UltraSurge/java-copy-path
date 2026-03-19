local M = {}

-- 全局配置存储
M.config = {
	keymap = "<leader>cp",              -- 默认快捷键
	include_generics = true,            -- 是否包含泛型信息
	include_params = false,             -- 是否包含参数信息
	float_window = {
		border = "rounded",             -- 边框样式: single, double, rounded, solid, shadow
		title_pos = "center",           -- 标题位置: left, center, right
		-- 高亮组配置
		highlights = {
			window = "Normal:JavaCopyPathFloat,FloatBorder:JavaCopyPathBorder",  -- 窗口和边框高亮
			selected = "JavaCopyPathSelected",    -- 选中项背景高亮
			label = "JavaCopyPathLabel",          -- 标签高亮 (Package:, Class: 等)
			value = "JavaCopyPathValue",          -- 值的高亮
			cursor = "JavaCopyPathCursor",        -- 光标指示器 (>)
		},
	},
	hide_options = {},                  -- 隐藏的选项列表
}

---@description 获取 Java 文件的包名
---从当前缓冲区的前 50 行中查找 package 声明
---@return string|nil 返回包名，如果未找到则返回 nil
---@example 对于 "package com.example.app;" 返回 "com.example.app"
local function get_package_name()
	-- 读取当前缓冲区的前 50 行（package 声明通常在文件开头）
	local lines = vim.api.nvim_buf_get_lines(0, 0, 50, false)

	-- 遍历每一行，查找 package 声明
	for _, line in ipairs(lines) do
		-- 使用 Lua 模式匹配提取包名
		-- 模式: "package" + 空格 + 包名(字母数字和点) + 分号
		local package = line:match("^package%s+([%w%.]+)%s*;")
		if package then
			return package
		end
	end

	return nil
end

---@description 获取当前光标所在的完整类路径（支持内部类）
---从当前光标位置向上查找所有类定义，返回完整的类路径链
---@return string|nil 返回完整类路径，如果未找到则返回 nil
---@example 对于内部类返回 "OuterClass.InnerClass"
local function get_class_name()
	-- 获取当前光标所在的行号
	local current_line = vim.fn.line(".")

	-- 读取整个缓冲区的所有行
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	-- 存储找到的所有类名（从内到外）
	local class_names = {}

	-- 跟踪大括号的嵌套层级，用于确定类的边界
	local brace_level = 0

	-- 从当前行向上查找所有类定义
	for i = current_line, 1, -1 do
		local line = lines[i]

		-- 计算大括号层级（向上遍历时反向计算）
		-- 统计当前行的大括号
		local open_braces = select(2, line:gsub("{", ""))
		local close_braces = select(2, line:gsub("}", ""))
		brace_level = brace_level + close_braces - open_braces

		-- 匹配类定义: class ClassName
		local class_name = line:match("class%s+([%w_]+)")

		-- 如果不是类，尝试匹配接口定义: interface InterfaceName
		if not class_name then
			class_name = line:match("interface%s+([%w_]+)")
		end

		-- 如果不是接口，尝试匹配枚举定义: enum EnumName
		if not class_name then
			class_name = line:match("enum%s+([%w_]+)")
		end

		-- 找到类名后添加到列表
		if class_name then
			table.insert(class_names, 1, class_name)  -- 插入到开头，保持从外到内的顺序
		end
	end

	-- 如果没有找到任何类名
	if #class_names == 0 then
		return nil
	end

	-- 返回完整的类路径（用点连接）
	-- 例如: OuterClass.InnerClass
	return table.concat(class_names, ".")
end

---@description 获取当前光标位置的词
---使用 Vim 的 expand 函数获取光标下的单词（WORD）
---@return string 返回光标下的单词
---@example 光标在 "createUser" 上时返回 "createUser"
local function get_word_under_cursor()
	-- 使用 Vim 特殊变量 <cword> 获取光标下的单词
	local word = vim.fn.expand("<cword>")
	return word
end

---@description 检查光标下的单词是否是方法，并提取泛型信息
---通过检查单词后是否有括号来判断是否为方法
---@return boolean is_method 是否为方法
---@return string|nil generics 泛型信息（如果有）
local function is_method()
	-- 获取当前行的完整文本
	local line = vim.api.nvim_get_current_line()

	-- 获取光标在当前行的列位置（从 0 开始）
	local col = vim.api.nvim_win_get_cursor(0)[2]

	-- 获取光标位置后的第一个字符
	local after_cursor = line:sub(col + 1, col + 1)

	-- 情况 1: 光标紧跟在 '(' 前面
	-- 例如: methodName|(args)  其中 | 表示光标位置
	if after_cursor == "(" then
		return true, nil
	end

	-- 情况 2: 光标后有空格，然后是 '('
	-- 例如: methodName |  (args)
	local remaining = line:sub(col + 1)
	if remaining:match("^%s*%(") then
		return true, nil
	end

	-- 情况 3: 检查整行是否包含 "单词名称 + 括号" 的模式
	-- 这处理了光标在单词中间或开头的情况
	local word = get_word_under_cursor()
	if line:match("%s+" .. word .. "%s*%(") or line:match("^%s*" .. word .. "%s*%(") then
		return true, nil
	end

	return false, nil
end

---@description 提取方法的泛型和参数信息
---分析当前行及后续行，提取完整的方法签名信息
---@return string|nil generics 泛型信息（如 "<T, E>"）
---@return string|nil params 参数信息（如 "(List<String> items, int count)"）
local function get_method_signature()
	local current_line_num = vim.fn.line(".")
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local word = get_word_under_cursor()

	-- 从当前行开始，向下查找完整的方法签名（可能跨多行）
	local signature = ""
	for i = current_line_num, math.min(current_line_num + 5, #lines) do
		signature = signature .. " " .. lines[i]
		-- 如果找到了方法体的开始或结束，停止
		if signature:match("{") or signature:match(";") then
			break
		end
	end

	-- 提取泛型信息
	-- 匹配 <T> 或 <T, E> 或 <T extends Comparable<T>>
	local generics = signature:match(word .. "%s*(<[^>]+>)%s*%(")

	-- 提取参数信息
	-- 匹配括号内的内容
	local params = signature:match(word .. "%s*<?[^>]*>?%s*(%([^)]*%))")

	return generics, params
end

---@description 获取当前文件的路径信息
---返回文件的绝对路径和相对路径
---@return string abs_path 文件的绝对路径
---@return string rel_path 文件相对于当前工作目录的路径
local function get_file_paths()
	-- 获取文件的绝对路径 (:p = 完整路径)
	local abs_path = vim.fn.expand("%:p")

	-- 获取文件的相对路径（默认相对于打开文件时的路径）
	local rel_path = vim.fn.expand("%")

	-- 获取当前工作目录
	local cwd = vim.fn.getcwd()

	-- 如果文件在当前工作目录下，计算相对于工作目录的路径
	if abs_path:sub(1, #cwd) == cwd then
		-- +2 是为了跳过路径分隔符（如 /）
		rel_path = abs_path:sub(#cwd + 2)
	end

	return abs_path, rel_path
end

---@description 复制文本到系统剪贴板
---将文本同时复制到多个剪贴板寄存器以确保兼容性
---@param text string 要复制的文本内容
local function copy_to_clipboard(text)
	-- 复制到 + 寄存器（系统剪贴板，适用于 X11）
	vim.fn.setreg("+", text)

	-- 复制到 * 寄存器（系统选择剪贴板，适用于 X11）
	vim.fn.setreg("*", text)

	-- 复制到默认的 unnamed 寄存器（Vim 内部剪贴板）
	vim.fn.setreg('"', text)
end

---@description 计算字符串的显示宽度
---处理多字节字符，返回实际的显示列数
---@param str string 要计算的字符串
---@return number 显示宽度
local function display_width(str)
	-- 使用 vim.fn.strdisplaywidth 获取实际显示宽度
	return vim.fn.strdisplaywidth(str)
end

---@description 截断过长的文本
---如果文本超过指定宽度，在中间添加省略号
---@param text string 要截断的文本
---@param max_width number 最大宽度
---@return string 截断后的文本
local function truncate_text(text, max_width)
	local width = display_width(text)
	if width <= max_width then
		return text
	end

	-- 预留省略号的空间
	local ellipsis = "..."
	local ellipsis_width = display_width(ellipsis)
	local available_width = max_width - ellipsis_width

	-- 分别计算前后部分各占多少宽度
	local half_width = math.floor(available_width / 2)

	-- 获取前半部分（从左往右取 half_width 宽度的字符）
	local left_chars = 0
	local left_bytes = 0
	local current_width = 0
	for i = 1, #text do
		local char = text:sub(i, i)
		local char_width = display_width(char)
		if current_width + char_width > half_width then
			break
		end
		current_width = current_width + char_width
		left_bytes = i
		left_chars = left_chars + 1
	end

	-- 获取后半部分（从右往左取 half_width 宽度的字符）
	local right_start = #text
	current_width = 0
	for i = #text, 1, -1 do
		local char = text:sub(i, i)
		local char_width = display_width(char)
		if current_width + char_width > half_width then
			break
		end
		current_width = current_width + char_width
		right_start = i
	end

	local left_part = text:sub(1, left_bytes)
	local right_part = text:sub(right_start)

	return left_part .. ellipsis .. right_part
end
local function setup_highlights()
	local hl = M.config.float_window.highlights

	-- 定义高亮组
	local highlights = {
		-- 浮动窗口边框 - 使用蓝色系
		JavaCopyPathBorder = { fg = "#61afef", bold = true },
		-- 浮动窗口背景 - 使用深色背景
		JavaCopyPathFloat = { bg = "#1e222a" },
		-- 选中项背景 - 使用高对比度的背景色
		JavaCopyPathSelected = { bg = "#2c313c", bold = true },
		-- 标签 - 使用紫色系 (Package:, Class: 等)
		JavaCopyPathLabel = { fg = "#c678dd", bold = true },
		-- 值 - 使用绿色系 (包名、类名等)
		JavaCopyPathValue = { fg = "#98c379" },
		-- 光标指示器 - 使用黄色
		JavaCopyPathCursor = { fg = "#e5c07b", bold = true },
		-- 窗口标题 - 使用青色
		JavaCopyPathTitle = { fg = "#56b6c2", bold = true },
		-- 底部提示文字 - 使用灰色
		JavaCopyPathHint = { fg = "#5c6370", italic = true },
	}

	-- 设置高亮组
	for name, opts in pairs(highlights) do
		vim.api.nvim_set_hl(0, name, opts)
	end
end

---@description 解析标签和值
---将 "Package: com.example" 解析为标签和值
---@param display string 显示文本
---@return string label 标签 (如 "Package:")
---@return string value 值 (如 "com.example")
local function parse_display(display)
	-- 匹配 "Label: value" 或 "Label (something): value" 格式
	local label, value = display:match("^([^:]+:)%s*(.+)$")
	if label and value then
		return label, value
	end
	return "", display
end

---@description 创建浮动窗口选择器
---显示一个居中的浮动窗口，让用户选择要复制的内容
---@param options table 选项列表，每个选项包含 display 和 value 字段
---@example options = {{display = "Package: com.example", value = "com.example"}}
local function show_selector(options)
	-- 设置高亮组
	setup_highlights()

	-- 创建命名空间用于高亮
	local ns_id = vim.api.nvim_create_namespace("java_copy_path")

	-- 创建一个临时的、不列出的缓冲区（false = 不列出, true = scratch buffer）
	local buf = vim.api.nvim_create_buf(false, true)

	-- 计算窗口所需的宽度
	-- 遍历所有选项，找出最长的显示文本
	local max_width = 0
	for _, opt in ipairs(options) do
		local display_text = opt.display or opt.value
		if #display_text > max_width then
			max_width = #display_text
		end
	end

	-- 设置窗口宽度和高度
	-- 宽度 = 最长文本 + 6（留出边距和光标指示器空间），但不超过屏幕宽度 - 10
	-- 同时确保宽度足够显示底部提示 "Enter: Confirm | Esc: Cancel"
	local hint_text = "Enter: Confirm | Esc: Cancel"
	local min_width_for_hint = #hint_text + 4
	local width = math.min(math.max(max_width + 6, min_width_for_hint), vim.o.columns - 10)
	-- 高度 = 选项数量 + 3（标题、底部提示和边框），但不超过屏幕高度 - 10
	local height = math.min(#options + 3, vim.o.lines - 10)

	-- 计算窗口位置（居中显示）
	-- row = 垂直居中位置
	local row = math.floor((vim.o.lines - height) / 2)
	-- col = 水平居中位置
	local col = math.floor((vim.o.columns - width) / 2)

	-- 窗口配置选项
	local opts = {
		relative = "editor",                        -- 相对于整个编辑器窗口定位
		width = width,                              -- 窗口宽度
		height = height,                            -- 窗口高度
		row = row,                                  -- 垂直位置
		col = col,                                  -- 水平位置
		style = "minimal",                          -- 最小化样式（无行号、状态栏等）
		border = M.config.float_window.border,      -- 边框样式（从配置读取）
		title = " Copy Reference ",                 -- 窗口标题
		title_pos = M.config.float_window.title_pos, -- 标题位置（从配置读取）
	}

	-- 创建浮动窗口并进入该窗口（true = 进入窗口）
	local win = vim.api.nvim_open_win(buf, true, opts)

	-- 设置窗口高亮组
	vim.wo[win].winhighlight = "Normal:JavaCopyPathFloat,FloatBorder:JavaCopyPathBorder,CursorLine:JavaCopyPathSelected"

	-- 设置窗口选项
	vim.wo[win].cursorline = true        -- 高亮当前行
	vim.wo[win].number = false           -- 不显示行号
	vim.wo[win].relativenumber = false   -- 不显示相对行号
	vim.wo[win].wrap = false             -- 不换行

	-- 当前选中的选项索引（从 1 开始）
	local selected = 1

	---@description 渲染选项列表到缓冲区
	---更新浮动窗口的显示内容，标记当前选中项
	local function render()
		-- 清除之前的高亮
		vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

		local lines = {}
		local display_lines = {}  -- 存储原始显示文本用于高亮计算

		-- 计算可用显示宽度（窗口宽度 - 前缀 - 边距）
		local max_display_width = width - 6

		-- 遍历所有选项，生成显示文本
		for i, opt in ipairs(options) do
			-- 当前选中的选项前面显示 "▸ "，其他显示 "  "
			local prefix = i == selected and "▸ " or "  "
			local display = opt.display or opt.value

			-- 截断过长的文本
			local truncated = truncate_text(display, max_display_width)

			table.insert(lines, prefix .. truncated)
			table.insert(display_lines, { full = display, shown = truncated, prefix = prefix })
		end

		-- 将生成的文本行设置到缓冲区
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

		-- 应用高亮
		for i, line_info in ipairs(display_lines) do
			local line_idx = i - 1  -- 0-indexed
			local display = line_info.full
			local shown = line_info.shown
			local prefix = line_info.prefix

			-- 高亮光标指示器 (▸)
			if i == selected then
				vim.api.nvim_buf_add_highlight(buf, ns_id, "JavaCopyPathCursor", line_idx, 0, 2)
			end

			-- 解析标签和值
			local label, value = parse_display(display)

			if label ~= "" then
				-- 使用 vim.fn.byteidx 获取正确的字节位置
				local prefix_width = #prefix  -- "▸ " 或 "  " 都是 2 字节

				-- 计算标签的字节位置
				local label_byte_start = prefix_width
				local label_byte_end = label_byte_start + #label

				-- 如果文本被截断了，需要调整高亮范围
				local shown_label, shown_value = parse_display(shown)
				if shown_label ~= "" then
					-- 重新计算基于实际显示文本的位置
					label_byte_end = label_byte_start + #shown_label

					-- 高亮标签
					vim.api.nvim_buf_add_highlight(buf, ns_id, "JavaCopyPathLabel", line_idx, label_byte_start, label_byte_end)

					-- 高亮值（从标签结束到行尾）
					vim.api.nvim_buf_add_highlight(buf, ns_id, "JavaCopyPathValue", line_idx, label_byte_end, -1)
				else
					-- 没有标签格式（可能是被截断了），整行使用值的高亮
					vim.api.nvim_buf_add_highlight(buf, ns_id, "JavaCopyPathValue", line_idx, prefix_width, -1)
				end
			else
				-- 没有标签格式，整行使用值的高亮
				vim.api.nvim_buf_add_highlight(buf, ns_id, "JavaCopyPathValue", line_idx, #prefix, -1)
			end
		end

		-- 添加底部提示行
		local hint = "Enter: Confirm | Esc: Cancel"
		local hint_line = string.rep(" ", math.floor((width - #hint) / 2)) .. hint
		vim.api.nvim_buf_set_lines(buf, #lines, -1, false, { hint_line })
		-- 为提示行添加高亮
		vim.api.nvim_buf_add_highlight(buf, ns_id, "JavaCopyPathHint", #lines, 0, -1)

		-- 移动光标到当前选中的行（行号, 列号）
		vim.api.nvim_win_set_cursor(win, { selected, 0 })
	end

	-- 设置缓冲区选项
	vim.bo[buf].modifiable = true    -- 允许修改（用于渲染内容）
	vim.bo[buf].bufhidden = "wipe"   -- 窗口关闭时自动删除缓冲区

	-- 初始渲染：首次显示选项列表
	render()

	---@description 关闭浮动窗口
	---检查窗口是否有效后关闭
	local function close()
		-- 检查窗口是否仍然有效（可能已被关闭）
		if vim.api.nvim_win_is_valid(win) then
			-- 强制关闭窗口（true = 强制关闭）
			vim.api.nvim_win_close(win, true)
		end
	end

	---@description 选择当前项并复制到剪贴板
	---执行复制操作后关闭窗口
	local function select_current()
		-- 获取当前选中的选项
		local option = options[selected]

		-- 验证选项和值是否有效
		if option and option.value and option.value ~= "" then
			-- 复制到剪贴板
			copy_to_clipboard(option.value)
			close()
			-- 显示成功通知
			vim.notify("Copied: " .. option.value, vim.log.levels.INFO)
		else
			close()
			-- 显示警告通知
			vim.notify("No value to copy", vim.log.levels.WARN)
		end
	end

	---@description 向上移动选择
	---循环选择：第一项时移动到最后一项
	local function move_up()
		selected = selected - 1

		-- 如果超出范围，循环到最后一项
		if selected < 1 then
			selected = #options
		end

		-- 重新渲染以更新显示
		render()
	end

	---@description 向下移动选择
	---循环选择：最后一项时移动到第一项
	local function move_down()
		selected = selected + 1

		-- 如果超出范围，循环到第一项
		if selected > #options then
			selected = 1
		end

		-- 重新渲染以更新显示
		render()
	end

	-- 设置键盘映射
	-- 定义浮动窗口中的所有快捷键
	local keymaps = {
		["<CR>"] = select_current,     -- Enter: 确认选择
		["l"] = select_current,         -- l: 确认选择（Vim 风格）
		["<Right>"] = select_current,   -- 右箭头: 确认选择
		["j"] = move_down,              -- j: 向下移动
		["<Down>"] = move_down,         -- 下箭头: 向下移动
		["k"] = move_up,                -- k: 向上移动
		["<Up>"] = move_up,             -- 上箭头: 向上移动
		["q"] = close,                  -- q: 退出窗口
		["<Esc>"] = close,              -- Esc: 退出窗口
	}

	-- 为每个快捷键设置键盘映射
	for key, func in pairs(keymaps) do
		vim.keymap.set("n", key, func, {
			buffer = buf,      -- 只在当前缓冲区生效
			nowait = true,     -- 不等待后续按键
			silent = true      -- 静默执行，不显示命令
		})
	end
end

---@description 复制 Java 路径到系统剪贴板（主函数）
---显示浮动窗口选择器，让用户选择要复制的内容
---支持复制：包名、类名、方法名、文件路径等
function M.copy_java_path()
	-- 获取当前缓冲区的文件类型
	local filetype = vim.bo.filetype

	-- 验证文件类型：只在 Java 文件中工作
	if filetype ~= "java" then
		vim.notify("This command only works in Java files", vim.log.levels.WARN)
		return
	end

	-- 收集所需的信息
	local package = get_package_name()           -- 获取包名
	local class = get_class_name()               -- 获取类名
	local word = get_word_under_cursor()         -- 获取光标下的单词
	local abs_path, rel_path = get_file_paths()  -- 获取文件路径

	-- 验证必要信息：包名
	if not package then
		vim.notify("Could not find package declaration", vim.log.levels.ERROR)
		return
	end

	-- 验证必要信息：类名
	if not class then
		vim.notify("Could not find class name", vim.log.levels.ERROR)
		return
	end

	-- 构建选项列表
	-- 每个选项包含 display（显示文本）和 value（实际值）
	local options = {}

	-- 选项 1: 包名
	-- 例如: "com.example.myapp.service"
	table.insert(options, {
		display = "Package: " .. package,
		value = package,
	})

	-- 选项 2: 类的完整路径（包名.类名）
	-- 例如: "com.example.myapp.service.UserService"
	local class_path = package .. "." .. class
	table.insert(options, {
		display = "Class: " .. class_path,
		value = class_path,
	})

	-- 选项 3: 当前光标位置的完整路径
	-- 根据光标位置动态生成（类、方法或字段）
	if word and word ~= "" then
		-- 提取类路径的最后一部分（处理内部类的情况）
		local class_parts = {}
		for part in class:gmatch("[^.]+") do
			table.insert(class_parts, part)
		end
		local last_class = class_parts[#class_parts]

		if word == last_class then
			-- 情况 3.1: 光标在类名上
			if not vim.tbl_contains(M.config.hide_options, "current") then
				table.insert(options, {
					display = "Current (Class): " .. class_path,
					value = class_path,
				})
			end
		else
			-- 情况 3.2: 光标在方法或字段上
			local current_path = package .. "." .. class .. "." .. word

			-- 判断是方法还是字段
			if is_method() then
				-- 如果启用了泛型支持，尝试获取方法签名
				local method_display = word
				if M.config.include_generics or M.config.include_params then
					local generics, params = get_method_signature()
					if M.config.include_generics and generics then
						method_display = method_display .. generics
					end
					if M.config.include_params and params then
						method_display = method_display .. params
					end
				end

				-- 方法路径
				-- 例如: "com.example.myapp.service.UserService.createUser"
				-- 或带泛型: "com.example.myapp.service.UserService.process<T>"
				if not vim.tbl_contains(M.config.hide_options, "current") then
					table.insert(options, {
						display = "Current (Method): " .. package .. "." .. class .. "." .. method_display,
						value = current_path,
					})
				end
			else
				-- 字段路径
				-- 例如: "com.example.myapp.service.UserService.repository"
				if not vim.tbl_contains(M.config.hide_options, "current") then
					table.insert(options, {
						display = "Current (Field): " .. current_path,
						value = current_path,
					})
				end
			end
		end
	end

	-- 选项 4: 文件相对路径
	-- 例如: "src/main/java/com/example/UserService.java"
	if not vim.tbl_contains(M.config.hide_options, "relative_path") then
		table.insert(options, {
			display = "Relative Path: " .. rel_path,
			value = rel_path,
		})
	end

	-- 选项 5: 文件绝对路径
	-- 例如: "/home/user/project/src/main/java/com/example/UserService.java"
	if not vim.tbl_contains(M.config.hide_options, "absolute_path") then
		table.insert(options, {
			display = "Absolute Path: " .. abs_path,
			value = abs_path,
		})
	end

	-- 显示选择器浮动窗口
	show_selector(options)
end

---@description 设置插件
---初始化插件配置并设置快捷键
---@param opts table|nil 配置选项，可选
---@field keymap string 快捷键映射，默认为 "<leader>cp"
---@field include_generics boolean 是否在方法路径中包含泛型信息，默认 true
---@field include_params boolean 是否在方法路径中包含参数信息，默认 false
---@field hide_options table 隐藏的选项列表，如 {"absolute_path", "relative_path"}
---@field float_window table 浮动窗口配置
---@example require("java-copy-path").setup({
---   keymap = "<leader>jcp",
---   include_generics = true,
---   include_params = false,
---   hide_options = {"absolute_path"},
---   float_window = { border = "double", title_pos = "left" }
--- })
function M.setup(opts)
	-- 合并用户配置和默认配置
	opts = opts or {}
	M.config = vim.tbl_deep_extend("force", M.config, opts)

	-- 获取快捷键配置
	local keymap = M.config.keymap

	-- 创建自动命令：只在打开 Java 文件时设置快捷键
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "java",  -- 文件类型模式：匹配 Java 文件
		callback = function()
			-- 在普通模式下设置快捷键
			vim.keymap.set("n", keymap, M.copy_java_path, {
				buffer = true,  -- 只在当前缓冲区生效
				desc = "Copy Java class/method path",  -- 快捷键描述（用于 which-key 等插件）
			})
		end,
	})
end

-- 返回模块表
return M
