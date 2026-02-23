-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                // straylight-llm // security/commandinjection
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--     "He'd operated on an almost permanent adrenaline high, a byproduct of
--      youth and proficiency, jacked into a custom cyberspace deck."
--
--                                                              — Neuromancer
--
-- Command injection prevention for agentic systems.
--
-- Hardened against known vulnerabilities:
--   - CVE-2024-6960: Docker PATH command injection
--   - CVE-2024-5478: sshNodeCommand injection
--   - CVE-2024-8374: cmd.exe bypass on Windows
--   - GHSA-4564-pvr2-qq4h: Shell injection in keychain writes
--
-- At billion-agent scale, every tool call is a potential attack vector.
-- Agents with x402 wallet access CANNOT be allowed to execute arbitrary shell.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module Security.CommandInjection
    ( -- * Shell Metacharacter Detection
      ShellMetachar
        ( MetaSemicolon
        , MetaPipe
        , MetaAmpersand
        , MetaDollar
        , MetaBacktick
        , MetaSubshell
        , MetaRedirectOut
        , MetaRedirectIn
        , MetaNewline
        , MetaNullByte
        , MetaBackslash
        , MetaQuote
        , MetaGlob
        )
    , detectShellMetachars
    , hasShellMetachars
    
      -- * Dangerous Command Detection
    , DangerousCommand
        ( DangerousFileDelete
        , DangerousFileModify
        , DangerousNetworkFetch
        , DangerousExec
        , DangerousPrivEsc
        , DangerousShell
        , DangerousEnvMod
        , DangerousSystemctl
        , DangerousDocker
        , DangerousKill
        , DangerousCrypto
        )
    , isDangerousCommand
    , dangerousCommands
    
      -- * Command Validation
    , CommandValidationResult
        ( CommandValid
        , CommandHasMetachars
        , CommandIsDangerous
        , CommandEmpty
        , CommandTooLong
        )
    , validateCommand
    , maxCommandLength
    
      -- * Safe Command Construction
    , SafeCommand (SafeCommand, unSafeCommand)
    , mkSafeCommand
    , safeCommandToList
    , sanitizeCommandArg
    
      -- * Environment Variable Safety
    , EnvVarResult
        ( EnvVarValid
        , EnvVarInvalidName
        , EnvVarDangerousValue
        )
    , validateEnvVar
    , sanitizeEnvValue
    , dangerousEnvVars
    ) where

import Data.Char (isAlphaNum, isAscii)
import Data.Text (Text)
import Data.Text qualified as T


-- ════════════════════════════════════════════════════════════════════════════
--                                              // shell metacharacter detection
-- ════════════════════════════════════════════════════════════════════════════

-- | Shell metacharacters that could enable injection
data ShellMetachar
    = MetaSemicolon      -- ^ Command separator (;)
    | MetaPipe           -- ^ Pipe (|)
    | MetaAmpersand      -- ^ Background/AND (&)
    | MetaDollar         -- ^ Variable expansion ($)
    | MetaBacktick       -- ^ Command substitution (`)
    | MetaSubshell       -- ^ Subshell ($())
    | MetaRedirectOut    -- ^ Output redirect (>)
    | MetaRedirectIn     -- ^ Input redirect (<)
    | MetaNewline        -- ^ Newline injection
    | MetaNullByte       -- ^ Null byte termination
    | MetaBackslash      -- ^ Escape sequences
    | MetaQuote          -- ^ Quote manipulation
    | MetaGlob           -- ^ Glob patterns (* ?)
    deriving (Show, Eq, Ord)

-- | All metacharacters to check
allMetachars :: [ShellMetachar]
allMetachars =
    [ MetaSemicolon
    , MetaPipe
    , MetaAmpersand
    , MetaDollar
    , MetaBacktick
    , MetaSubshell
    , MetaRedirectOut
    , MetaRedirectIn
    , MetaNewline
    , MetaNullByte
    , MetaBackslash
    , MetaQuote
    , MetaGlob
    ]

-- | Check if text contains a specific metacharacter
hasMetachar :: Text -> ShellMetachar -> Bool
hasMetachar txt = \case
    MetaSemicolon   -> T.any (== ';') txt
    MetaPipe        -> T.any (== '|') txt
    MetaAmpersand   -> T.any (== '&') txt
    MetaDollar      -> T.any (== '$') txt
    MetaBacktick    -> T.any (== '`') txt
    MetaSubshell    -> "$(" `T.isInfixOf` txt
    MetaRedirectOut -> T.any (== '>') txt
    MetaRedirectIn  -> T.any (== '<') txt
    MetaNewline     -> T.any (== '\n') txt || T.any (== '\r') txt
    MetaNullByte    -> T.any (== '\0') txt
    MetaBackslash   -> T.any (== '\\') txt
    MetaQuote       -> T.any (\c -> c == '"' || c == '\'') txt
    MetaGlob        -> T.any (\c -> c == '*' || c == '?') txt

-- | Detect all shell metacharacters in text
detectShellMetachars :: Text -> [ShellMetachar]
detectShellMetachars t = filter (hasMetachar t) allMetachars

-- | Quick check for any shell metacharacters
hasShellMetachars :: Text -> Bool
hasShellMetachars = not . null . detectShellMetachars


-- ════════════════════════════════════════════════════════════════════════════
--                                                // dangerous command detection
-- ════════════════════════════════════════════════════════════════════════════

-- | Categories of dangerous commands
data DangerousCommand
    = DangerousFileDelete    -- ^ rm, del, unlink
    | DangerousFileModify    -- ^ chmod, chown, attrib
    | DangerousNetworkFetch  -- ^ curl, wget, nc
    | DangerousExec          -- ^ eval, exec, source
    | DangerousPrivEsc       -- ^ sudo, su, doas, runas
    | DangerousShell         -- ^ sh, bash, cmd, powershell
    | DangerousEnvMod        -- ^ export, set, env
    | DangerousSystemctl     -- ^ systemctl, service
    | DangerousDocker        -- ^ docker, podman
    | DangerousKill          -- ^ kill, pkill, killall
    | DangerousCrypto        -- ^ gpg, openssl (key manipulation)
    deriving (Show, Eq, Ord)

-- | List of dangerous commands by category
dangerousCommands :: [(DangerousCommand, [Text])]
dangerousCommands =
    [ (DangerousFileDelete,   ["rm", "rmdir", "del", "unlink", "shred", "wipe"])
    , (DangerousFileModify,   ["chmod", "chown", "chgrp", "attrib", "icacls", "setfacl"])
    , (DangerousNetworkFetch, ["curl", "wget", "nc", "netcat", "ncat", "fetch", "aria2c"])
    , (DangerousExec,         ["eval", "exec", "source", ".", "xargs", "parallel"])
    , (DangerousPrivEsc,      ["sudo", "su", "doas", "runas", "pkexec", "gksudo"])
    , (DangerousShell,        ["sh", "bash", "zsh", "fish", "dash", "ksh", "tcsh",
                               "cmd", "cmd.exe", "powershell", "pwsh", "powershell.exe"])
    , (DangerousEnvMod,       ["export", "set", "setenv", "unset", "env"])
    , (DangerousSystemctl,    ["systemctl", "service", "init", "launchctl", "rc-service"])
    , (DangerousDocker,       ["docker", "podman", "nerdctl", "containerd", "ctr", "crictl"])
    , (DangerousKill,         ["kill", "pkill", "killall", "taskkill", "xkill"])
    , (DangerousCrypto,       ["gpg", "openssl", "ssh-keygen", "ssh-add", "keychain"])
    ]

-- | Check if a command is dangerous
isDangerousCommand :: Text -> Maybe DangerousCommand
isDangerousCommand cmd =
    let normalized = T.toLower $ T.strip cmd
        -- Extract base command (handle paths like /usr/bin/rm)
        baseName = last $ T.splitOn "/" normalized
    in lookup baseName flatList
  where
    flatList :: [(Text, DangerousCommand)]
    flatList = concatMap (\(cat, cmds) -> map (\c -> (c, cat)) cmds) dangerousCommands


-- ════════════════════════════════════════════════════════════════════════════
--                                                       // command validation
-- ════════════════════════════════════════════════════════════════════════════

-- | Result of command validation
data CommandValidationResult
    = CommandValid
    | CommandHasMetachars ![ShellMetachar]
    | CommandIsDangerous !DangerousCommand
    | CommandEmpty
    | CommandTooLong !Int  -- ^ Length exceeded limit
    deriving (Show, Eq)

-- | Maximum command length (prevent DoS)
-- At 1000 tokens/sec with millions of agents, command length must be bounded
maxCommandLength :: Int
maxCommandLength = 10000

-- | Validate a command for injection attacks
--
-- SECURITY: Checks for:
-- - Shell metacharacters that could enable injection
-- - Dangerous commands that could damage the system
-- - Null bytes and other control characters
-- - Excessive length (DoS prevention)
--
-- This is the PRIMARY defense against malicious tool calls from agents
-- operating with x402 wallet access.
validateCommand :: Text -> CommandValidationResult
validateCommand cmd
    | T.null (T.strip cmd) = CommandEmpty
    | T.length cmd > maxCommandLength = CommandTooLong (T.length cmd)
    | not (null metas) = CommandHasMetachars metas
    | Just danger <- isDangerousCommand firstWord = CommandIsDangerous danger
    | otherwise = CommandValid
  where
    metas = detectShellMetachars cmd
    firstWord = T.takeWhile (not . (`elem` [' ', '\t'])) (T.strip cmd)


-- ════════════════════════════════════════════════════════════════════════════
--                                                 // safe command construction
-- ════════════════════════════════════════════════════════════════════════════

-- | A command that has been validated as safe
newtype SafeCommand = SafeCommand
    { unSafeCommand :: (Text, [Text])  -- ^ (executable, arguments)
    }
    deriving (Show, Eq)

-- | Construct a safe command from executable and arguments
--
-- SECURITY: Each argument is individually validated and sanitized.
-- The executable must not contain path traversal or metacharacters.
mkSafeCommand :: Text -> [Text] -> Either Text SafeCommand
mkSafeCommand exe args
    | T.null exe = Left "Empty executable"
    | hasShellMetachars exe = Left "Executable contains shell metacharacters"
    | ".." `T.isInfixOf` exe = Left "Executable contains path traversal"
    | any hasShellMetachars args = Left "Argument contains shell metacharacters"
    | otherwise = Right $ SafeCommand (exe, map sanitizeCommandArg args)

-- | Convert safe command to list for exec
safeCommandToList :: SafeCommand -> [Text]
safeCommandToList (SafeCommand (exe, args)) = exe : args

-- | Sanitize a command argument
--
-- Removes dangerous characters while preserving safe ones.
-- This is a WHITELIST approach - only known-safe chars pass through.
sanitizeCommandArg :: Text -> Text
sanitizeCommandArg = T.filter isSafeChar
  where
    isSafeChar c =
        isAlphaNum c
            || c == '-'
            || c == '_'
            || c == '.'
            || c == '/'
            || c == ':'
            || c == '='
            || c == ','
            || c == ' '


-- ════════════════════════════════════════════════════════════════════════════
--                                                // environment variable safety
-- ════════════════════════════════════════════════════════════════════════════

-- | Result of environment variable validation
data EnvVarResult
    = EnvVarValid
    | EnvVarInvalidName !Text
    | EnvVarDangerousValue !Text
    deriving (Show, Eq)

-- | Dangerous environment variable names
--
-- These can lead to code execution or privilege escalation if modified.
-- Reference: CVE-2024-6960 (Docker PATH command injection)
dangerousEnvVars :: [Text]
dangerousEnvVars =
    [ "PATH"
    , "LD_PRELOAD"
    , "LD_LIBRARY_PATH"
    , "DYLD_INSERT_LIBRARIES"
    , "DYLD_LIBRARY_PATH"
    , "PYTHONPATH"
    , "NODE_PATH"
    , "PERL5LIB"
    , "RUBYLIB"
    , "CLASSPATH"
    , "HOME"
    , "USER"
    , "SHELL"
    , "IFS"
    , "ENV"
    , "BASH_ENV"
    , "PS1"
    , "PROMPT_COMMAND"
    -- x402/wallet specific
    , "WALLET_PRIVATE_KEY"
    , "AGENT_SECRET"
    , "API_KEY"
    , "AUTH_TOKEN"
    ]

-- | Validate an environment variable
--
-- SECURITY: Blocks modification of dangerous environment variables
-- that could lead to code execution or privilege escalation.
validateEnvVar :: Text -> Text -> EnvVarResult
validateEnvVar name value
    | T.toUpper name `elem` map T.toUpper dangerousEnvVars =
        EnvVarInvalidName name
    | hasShellMetachars value =
        EnvVarDangerousValue "Value contains shell metacharacters"
    | otherwise = EnvVarValid

-- | Sanitize an environment variable value
sanitizeEnvValue :: Text -> Text
sanitizeEnvValue = T.filter isSafeEnvChar
  where
    isSafeEnvChar c =
        isAscii c
            && (isAlphaNum c || c `elem` ['-', '_', '.', '/', ':', '=', ',', ' '])
