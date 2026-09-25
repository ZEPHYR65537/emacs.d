# Gnus 邮件与可选加密凭据

`init-mail` 经 Purcell 的 `init-personal` 模块列表加载。使用 Emacs 内置的
Gnus、nnimap、smtpmail 和 auth-source，不引入另一套包管理器。
启动 Emacs 不会连接邮箱、解密凭据或询问密码。

## 配置与使用

- `C-c m` / `M-x sanityinc/mail`：打开邮件前端；首次使用时在本机设置账户。
- `M-x sanityinc/mail-configure-account`：修改服务器、端口、TLS 方式及身份。
  修改前先用 `q` 退出 Gnus。已启用持久化时会重新询问密码及加密口令并更新密文。
- `M-x sanityinc/mail-compose`：写信。附件用 `C-c C-a`，发送用 `C-c C-c`。

服务器和身份均由用户输入，仓库中没有实际域名、邮箱或用户名。
IMAP/SMTP 可以使用不同主机名和自定义端口；当前支持一个主账户、共享的登录名及密码。

| 方式 | 含义 | 常见端口，仅为默认值 |
|---|---|---|
| IMAP `tls` | 直接建立 TLS | 993 |
| IMAP `starttls` | 必须成功升级 TLS | 143 |
| SMTP `tls` | 直接建立 TLS | 465 |
| SMTP `starttls` | 必须成功升级 TLS | 587 |

两种方式都严格校验证书和主机名，不回退到明文认证。
TLS compatibility 默认选择 `default`；仅当确认有协商兼容问题时选 `tls12`。
兼容选项只作用于配置的邮箱连接，仍保留证书验证。

如文件夹列表为空，在 Gnus 分组列表按 `^` 打开服务器列表，进入账户，
用 `u` 订阅 INBOX。`g` 刷新、`L` 显示已订阅文件夹（含无未读）、回车打开，
`r` 回复、`q` 返回。配置或安装过程不会发送测试邮件。

## 默认：仅当前会话

不主动保存账户或密码。邮箱身份的输入不进入 minibuffer 历史；密码通过
`read-passwd` 遮蔽输入，并由 auth-source 在内存缓存一小时。
重启后重新输入；IMAP/SMTP 的缓存独立，首次使用可能分别提示密码。

此账户的认证不会读取普通 authinfo/netrc、环境变量中的密码或其他应用的凭据文件。
其他账户和应用的 auth-source 设置保持原样。

## 可选：GnuPG 加密持久化，Windows / Linux 通用

1. 运行 `M-x sanityinc/mail-enable-persistence`。
2. 在本机输入并确认邮箱密码。
3. 选择并确认一个**独立的保险库解锁口令**。该口令不会保存到磁盘。
4. 此后重启 Emacs，第一次进入邮箱只需解锁一次；服务器设置、邮箱身份和密码
   从加密文件恢复，不再逐项询问。

本次解锁后的凭据保留在 Emacs 内存，直到主动锁定或退出。
锁定：`M-x sanityinc/mail-forget-passwords`。这会清除账户缓存及保险库内存，
不删除密文，也不会断开已经认证的连接。

更换密码或解锁口令：再次运行 `sanityinc/mail-enable-persistence`。
关闭持久化：`M-x sanityinc/mail-disable-persistence`，只删除 `account.gpg`，
保留邮件、草稿、GPG 工作目录，恢复仅会话模式。请自行处理其他设备和备份中的副本。

默认密文路径：

```text
~/.local/share/emacs/mail/credentials/account.gpg
```

设置了 `XDG_DATA_HOME` 时，使用其下的 `emacs/mail/credentials/account.gpg`。
也可在本机配置 `sanityinc/mail-vault-directory`。文件不属于 Emacs 配置仓库；
即使是密文，也不要提交到 Git。

迁移到另一台 Windows/Linux：安装 GnuPG 2.x、启用相同模块，把 **account.gpg**
复制到另一台机器的相应位置，输入相同解锁口令即可。无需 Windows 凭据管理器、
DPAPI 或复制私钥；不需要同步旁边的 `gpg-home/` 目录。
解锁口令丢失时无法恢复此文件，但可关闭持久化并重新输入邮箱凭据。

### GPG 可执行程序

优先在 PATH 中寻找 `gpg` / `gpg2`。Windows 也会尝试已有的 Git for Windows、
Scoop Git 或 GnuPG 的常见安装位置。必要时只在本机设置
`sanityinc/mail-gpg-program` 为 GPG 路径；这不是账户信息或密码。

### 存储边界

- 使用标准 OpenPGP 对称加密（AES256，带盐、迭代的口令派生）。
- 账户设置、邮箱身份和密码一起加密；解锁口令不在配置、参数或环境变量中。
- 加解密使用 GPG 的 stdin/stdout 内存管道；不用 `call-process-region` 或
  `epg-decrypt-string`，避免其可能涉及的明文临时文件路径。
- 原子替换文件也只含密文；POSIX 上目录权限设为 0700，文件为 0600。
- 不创建承载明文的 Emacs 文件缓冲区、自动保存文件或明文备份；不输出 GPG
  的原始错误内容或认证调试日志。
- 使用时明文凭据必须短暂存在于进程内存。加密文件不能防御已控制当前用户会话的程序。

## 邮件状态与排错

默认状态目录：`~/.local/share/emacs/mail/state/`（支持 `XDG_DATA_HOME`）。
已有会话/本机自定义的 `sanityinc/mail-state-directory` 可继续使用，不自动迁移邮件。
草稿和本地已发送副本留在状态目录；已发送副本是本地 nnfolder 的 `sent` 分组，
不会自动追加到服务器 Sent 文件夹。自动过期删除已禁用。

持久化仅解决账户信息的重复输入，不修复服务器端口、TLS 或投递故障。
发送卡住可用 `C-g` 中断；原邮件投递状态不明时先核对服务器日志，再决定是否重发。
不要把认证缓冲区、解密结果、私钥或完整调试回溯粘贴到聊天/公开 issue。

离线测试（只使用隔离的假数据，不读取真实保险库；需要 GnuPG）：

```sh
emacs --batch -Q -L lisp -l tests/init-mail-test.el -f ert-run-tests-batch-and-exit
```

移除 `init-personal` 列表中的 `init-mail` 并重启，可停止加载。

参考：
- https://github.com/purcell/emacs.d
- https://www.gnu.org/software/emacs/manual/html_mono/gnus.html
- https://www.gnupg.org/documentation/manuals/gnupg/GPG-Esoteric-Options.html
