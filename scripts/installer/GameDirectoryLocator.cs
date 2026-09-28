using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace OctopathDialogueAssistantInstaller
{
    internal sealed class GameDirectorySearchResult
    {
        public bool Remembered;
        public string[] Directories;
    }

    internal static class GameDirectoryLocator
    {
        private const string AppId = "1971650";
        private const string PreferenceKey = @"Software\OctopathDialogueAssistant\Installer";
        private const string PreferenceValue = "GameRoot";

        public static bool TryGetGameRoot(string candidate, out string root)
        {
            root = null;
            if (string.IsNullOrWhiteSpace(candidate)) return false;
            try
            {
                string path = Path.GetFullPath(candidate.Trim());
                string executable = Path.Combine(path, "Octopath_Traveler2", "Binaries", "Win64",
                    "Octopath_Traveler2-Win64-Shipping.exe");
                if (!File.Exists(executable)) return false;
                root = NormalizePath(path);
                return true;
            }
            catch (Exception)
            {
                return false;
            }
        }

        public static bool Remember(string candidate, out string error)
        {
            error = null;
            string root;
            if (!TryGetGameRoot(candidate, out root)) return false;
            try
            {
                using (RegistryKey key = Registry.CurrentUser.CreateSubKey(PreferenceKey))
                {
                    key.SetValue(PreferenceValue, root, RegistryValueKind.String);
                }
                return true;
            }
            catch (Exception exception)
            {
                error = exception.Message;
                return false;
            }
        }

        public static GameDirectorySearchResult Find()
        {
            string remembered;
            if (TryGetGameRoot(ReadRegistry(RegistryHive.CurrentUser, RegistryView.Default,
                PreferenceKey, PreferenceValue), out remembered))
            {
                return new GameDirectorySearchResult { Remembered = true, Directories = new[] { remembered } };
            }

            HashSet<string> games = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            HashSet<string> steamRoots = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            AddAbsolutePath(steamRoots, ReadRegistry(RegistryHive.CurrentUser, RegistryView.Default,
                @"Software\Valve\Steam", "SteamPath"));
            foreach (RegistryView view in new[] { RegistryView.Registry32, RegistryView.Registry64 })
            {
                AddAbsolutePath(steamRoots, ReadRegistry(RegistryHive.LocalMachine, view,
                    @"Software\Valve\Steam", "InstallPath"));
                AddGame(games, ReadRegistry(RegistryHive.LocalMachine, view,
                    @"Software\Microsoft\Windows\CurrentVersion\Uninstall\Steam App " + AppId, "InstallLocation"));
            }
            foreach (Environment.SpecialFolder folder in new[] {
                Environment.SpecialFolder.ProgramFilesX86, Environment.SpecialFolder.ProgramFiles })
            {
                string parent = Environment.GetFolderPath(folder);
                if (!string.IsNullOrEmpty(parent)) AddAbsolutePath(steamRoots, Path.Combine(parent, "Steam"));
            }

            HashSet<string> libraries = new HashSet<string>(steamRoots, StringComparer.OrdinalIgnoreCase);
            foreach (string steamRoot in steamRoots)
            {
                string text = ReadText(Path.Combine(steamRoot, "steamapps", "libraryfolders.vdf"));
                foreach (string path in LibraryPaths(text)) AddAbsolutePath(libraries, path);
            }
            foreach (string library in libraries)
            {
                string text = ReadText(Path.Combine(library, "steamapps", "appmanifest_" + AppId + ".acf"));
                string directory = InstallDirectory(text);
                if (directory != null) AddGame(games, Path.Combine(library, "steamapps", "common", directory));
            }

            string[] directories = new string[games.Count];
            games.CopyTo(directories);
            Array.Sort(directories, StringComparer.OrdinalIgnoreCase);
            return new GameDirectorySearchResult { Directories = directories };
        }

        private static void AddGame(HashSet<string> games, string candidate)
        {
            string root;
            if (TryGetGameRoot(candidate, out root)) games.Add(root);
        }

        private static void AddAbsolutePath(HashSet<string> paths, string candidate)
        {
            if (string.IsNullOrWhiteSpace(candidate)) return;
            try
            {
                // Ignore relative or drive-relative entries; never scan drives recursively.
                if (!Regex.IsMatch(candidate, @"^(?:[A-Za-z]:[\\/]|\\\\)")) return;
                paths.Add(NormalizePath(candidate));
            }
            catch (Exception) { }
        }

        private static string NormalizePath(string path)
        {
            string full = Path.GetFullPath(path);
            string trimmed = full.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            return trimmed.Length < Path.GetPathRoot(full).Length ? Path.GetPathRoot(full) : trimmed;
        }

        private static string ReadRegistry(RegistryHive hive, RegistryView view, string path, string name)
        {
            try
            {
                using (RegistryKey root = RegistryKey.OpenBaseKey(hive, view))
                using (RegistryKey key = root.OpenSubKey(path))
                {
                    return key == null ? null : key.GetValue(name) as string;
                }
            }
            catch (Exception) { return null; }
        }

        private static string ReadText(string path)
        {
            try { return File.ReadAllText(path, Encoding.UTF8); }
            catch (Exception) { return string.Empty; }
        }

        private static IEnumerable<string> Values(string text, string key)
        {
            // Steam's quoted KeyValues fields: unescape only quotes and backslashes, not Unicode.
            string pattern = @"(?im)^\s*""" + Regex.Escape(key) + @"""\s*""((?:\\.|[^""\\\r\n])*)""";
            foreach (Match match in Regex.Matches(text ?? string.Empty, pattern))
            {
                yield return Regex.Replace(match.Groups[1].Value, @"\\([\\""])", "$1");
            }
        }

        internal static string[] LibraryPaths(string text)
        {
            return new List<string>(Values(text, "path")).ToArray();
        }

        internal static string InstallDirectory(string text)
        {
            List<string> ids = new List<string>(Values(text, "appid"));
            List<string> names = new List<string>(Values(text, "installdir"));
            if (ids.Count != 1 || ids[0] != AppId || names.Count != 1) return null;
            string name = names[0];
            if (string.IsNullOrWhiteSpace(name) || name == "." || name == ".."
                || name.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0) return null;
            return name;
        }
    }
}
