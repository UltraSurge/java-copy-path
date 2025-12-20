# jcopy

一个用于在 Java 文件中快速复制完整类路径和方法路径的 Neovim 插件。

## ✨ 功能特性

- 🎯 **浮动窗口选择器** - 显示美观的浮动窗口，让你选择要复制的内容
- 📦 **包名复制** - 复制当前文件的包名
- 🏷️ **类路径复制** - 完整支持内部类（如：`com.example.OuterClass.InnerClass`）
- 🔧 **方法路径复制** - 支持泛型方法和参数信息
  - 基础方法：`com.example.MyClass.method`
  - 带泛型：`com.example.MyClass.process<T>`
  - 带参数：`com.example.MyClass.findMax(List<T> items)`
- 📄 **文件路径复制** - 支持复制文件的相对路径和绝对路径
- ⚙️ **高度可配置** - 自定义快捷键、边框样式、显示选项等
- ⌨️ **键盘导航** - 使用 `j/k` 或方向键选择，`Enter` 或 `l` 确认
- 📋 **系统剪贴板** - 自动复制到系统剪贴板

## 📦 安装

### LazyVim / lazy.nvim（推荐）

在 `~/.config/nvim/lua/plugins/` 创建 `jcopy.lua` 文件：

```lua
return {
  "UltraSurge/java-copy-path",
  ft = "java",
  keys = {
    {
      "<leader>cp",
      function()
        require("java-copy-path").copy_java_path()
      end,
      desc = "Copy Java class/method path",
      ft = "java",
    },
  },
  config = function()
    require("java-copy-path").setup()
  end,
}
```

### packer.nvim

```lua
use {
  "UltraSurge/java-copy-path",
  ft = "java",
  config = function()
    require("java-copy-path").setup()
  end
}
```

### vim-plug

```vim
Plug 'UltraSurge/java-copy-path'
```

然后在 init.lua 中添加：

```lua
require("java-copy-path").setup()
```

## 🚀 使用方法

### 基本操作

1. 在 Java 文件中，将光标移动到任意位置
2. 按下 `<leader>cp`（LazyVim 中是 `Space + c + p`）
3. 浮动窗口会显示可复制的选项
4. 使用 `j/k` 或方向键上下选择
5. 按 `Enter` 或 `l` 确认复制
6. 按 `q` 或 `Esc` 取消

### 浮动窗口

插件会根据当前光标位置智能显示以下选项：

```
╭──────── Select what to copy ────────╮
│ > Package: com.example.myapp.service│
│   Class: com.example.myapp.service.UserService│
│   Current (Method): com.example.myapp.service.UserService.createUser│
│   Relative Path: src/main/java/UserService.java│
│   Absolute Path: /home/user/project/src/main/java/UserService.java│
╰─────────────────────────────────────╯
```

**选项说明：**

- **Package** - 当前文件的包名
- **Class** - 完整的类路径（支持内部类）
- **Current** - 光标所在位置的完整路径（类/方法/字段）
- **Relative Path** - 文件相对路径
- **Absolute Path** - 文件绝对路径

### 键盘快捷键

**在浮动窗口中：**

- `j` / `↓` - 向下移动
- `k` / `↑` - 向上移动
- `Enter` / `l` / `→` - 选择并复制
- `q` / `Esc` - 取消

## 📝 使用示例

### 基础示例

```java
package com.example.myapp.service;

public class UserService {
    private UserRepository repository;

    public void createUser() {
        // ...
    }
}
```

- 光标在 `UserService` 上，按 `<leader>cp` → 选择 "Class"
- 复制：`com.example.myapp.service.UserService`

- 光标在 `createUser` 上，按 `<leader>cp` → 选择 "Current (Method)"
- 复制：`com.example.myapp.service.UserService.createUser`

### 内部类支持

```java
package com.example.demo;

public class OuterClass {
    public class InnerClass {
        public void process() {
            // ...
        }

        public class NestedClass {
            public void execute() {
                // ...
            }
        }
    }
}
```

**复制内部类路径：**

- 光标在 `InnerClass` 上 → `com.example.demo.OuterClass.InnerClass`

**复制嵌套内部类：**

- 光标在 `NestedClass` 上 → `com.example.demo.OuterClass.InnerClass.NestedClass`

**复制内部类方法：**

- 光标在 `process` 上 → `com.example.demo.OuterClass.InnerClass.process`

### 泛型方法支持

```java
public class GenericService {
    public <T> T process(T item) {
        return item;
    }

    public <K, V> void put(K key, V value) {
        // ...
    }
}
```

**默认配置（显示泛型）：**

- 浮动窗口显示：`Current (Method): com.example.GenericService.process<T>`
- 实际复制：`com.example.GenericService.process`

**启用参数显示：**

- 浮动窗口显示：`Current (Method): com.example.GenericService.put<K, V>(K key, V value)`
- 实际复制：`com.example.GenericService.put`

## ⚙️ 配置

### 完整配置示例

```lua
require("java-copy-path").setup({
  -- 快捷键设置
  keymap = "<leader>cp",

  -- 泛型和参数支持
  include_generics = true,   -- 是否显示泛型信息，默认: true
  include_params = false,    -- 是否显示参数信息，默认: false

  -- 隐藏特定选项
  hide_options = {
    -- "package",              -- 隐藏包名选项
    -- "class",                -- 隐藏类路径选项
    -- "current",              -- 隐藏当前光标选项
    -- "relative_path",        -- 隐藏相对路径选项
    "absolute_path",           -- 隐藏绝对路径选项
  },

  -- 浮动窗口样式
  float_window = {
    border = "rounded",        -- 边框: single, double, rounded, solid, shadow
    title_pos = "center",      -- 标题位置: left, center, right
  },
})
```

### 快速配置

**只修改快捷键：**

```lua
require("java-copy-path").setup({
  keymap = "<leader>yp"
})
```

**显示完整方法签名：**

```lua
require("java-copy-path").setup({
  include_generics = true,
  include_params = true,
})
```

**简化选项列表：**

```lua
require("java-copy-path").setup({
  hide_options = { "package", "relative_path", "absolute_path" },
})
```

**自定义窗口样式：**

```lua
require("java-copy-path").setup({
  float_window = {
    border = "double",
    title_pos = "left",
  },
})
```

## 📋 系统要求

- Neovim >= 0.7.0
- 系统剪贴板支持

### 检查剪贴板支持

```vim
:checkhealth clipboard
```

**Linux 需要安装剪贴板工具：**

```bash
# Ubuntu/Debian
sudo apt install xclip

# Arch Linux
sudo pacman -S xclip
```

**macOS 和 Windows：** 剪贴板通常已经内置支持。

## 🔧 故障排除

### 插件没有反应

1. 确认文件类型：`:set filetype?` 应该显示 `filetype=java`
2. 手动测试：`:lua require("java-copy-path").copy_java_path()`
3. 查看错误：`:messages`

### 找不到包名

确保 Java 文件有正确的 `package` 声明：

```java
package com.example.myapp;
```

### LazyVim 相关

**检查插件是否加载：**

```vim
:Lazy
```

**检查快捷键：**

```vim
:map <leader>cp
```

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

## 👤 作者

**WD.chu** - <creedon.cn@gmail.com>

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## ⭐ Star History

如果这个插件对你有帮助，请给个 star！
