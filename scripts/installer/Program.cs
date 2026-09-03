using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Octopath Dialogue Assistant Installer")]
[assembly: AssemblyProduct("Octopath Dialogue Assistant")]
[assembly: AssemblyVersion("1.0.0.0")]

namespace OctopathDialogueAssistantInstaller
{
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new InstallerForm());
        }
    }

    internal sealed class InstallerForm : Form
    {
        private readonly string packageRoot;
        private readonly TextBox gameRootTextBox;
        private readonly Button browseButton;
        private readonly Button installButton;
        private readonly Button uninstallButton;
        private readonly Label statusLabel;
        private readonly RichTextBox outputTextBox;
        private bool running;

        public InstallerForm()
        {
            packageRoot = AppDomain.CurrentDomain.BaseDirectory;

            Text = "Octopath Dialogue Assistant 安装器";
            ClientSize = new Size(720, 470);
            MinimumSize = new Size(680, 430);
            StartPosition = FormStartPosition.CenterScreen;
            Font = new Font("Microsoft YaHei UI", 9F, FontStyle.Regular, GraphicsUnit.Point);
            FormClosing += InstallerFormClosing;

            Label titleLabel = new Label();
            titleLabel.AutoSize = true;
            titleLabel.Font = new Font(Font.FontFamily, 16F, FontStyle.Bold);
            titleLabel.Location = new Point(24, 20);
            titleLabel.Text = "Octopath Dialogue Assistant";
            Controls.Add(titleLabel);

            Label pathLabel = new Label();
            pathLabel.AutoSize = true;
            pathLabel.Location = new Point(26, 70);
            pathLabel.Text = "游戏目录（Steam common 下的 Octopath_Traveler2 文件夹）";
            Controls.Add(pathLabel);

            gameRootTextBox = new TextBox();
            gameRootTextBox.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            gameRootTextBox.Location = new Point(28, 96);
            gameRootTextBox.Size = new Size(568, 23);
            Controls.Add(gameRootTextBox);

            browseButton = new Button();
            browseButton.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            browseButton.Location = new Point(606, 94);
            browseButton.Size = new Size(88, 28);
            browseButton.Text = "选择目录";
            browseButton.UseVisualStyleBackColor = true;
            browseButton.Click += BrowseButtonClick;
            Controls.Add(browseButton);

            installButton = new Button();
            installButton.Location = new Point(28, 142);
            installButton.Size = new Size(132, 38);
            installButton.Text = "安装 / 更新";
            installButton.UseVisualStyleBackColor = true;
            installButton.Click += delegate { RunInstallerScript("install.ps1", "安装"); };
            Controls.Add(installButton);

            uninstallButton = new Button();
            uninstallButton.Location = new Point(174, 142);
            uninstallButton.Size = new Size(132, 38);
            uninstallButton.Text = "卸载";
            uninstallButton.UseVisualStyleBackColor = true;
            uninstallButton.Click += delegate { RunInstallerScript("uninstall.ps1", "卸载"); };
            Controls.Add(uninstallButton);

            statusLabel = new Label();
            statusLabel.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            statusLabel.Location = new Point(326, 151);
            statusLabel.Size = new Size(368, 24);
            statusLabel.TextAlign = ContentAlignment.MiddleRight;
            statusLabel.Text = "请选择游戏目录";
            Controls.Add(statusLabel);

            outputTextBox = new RichTextBox();
            outputTextBox.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
            outputTextBox.BackColor = Color.FromArgb(247, 247, 247);
            outputTextBox.BorderStyle = BorderStyle.FixedSingle;
            outputTextBox.Font = new Font("Consolas", 9F, FontStyle.Regular, GraphicsUnit.Point);
            outputTextBox.Location = new Point(28, 200);
            outputTextBox.ReadOnly = true;
            outputTextBox.Size = new Size(666, 238);
            outputTextBox.Text = "安装器会调用同目录 scripts 文件夹中的安装或卸载脚本。\r\n";
            Controls.Add(outputTextBox);
        }

        private void InstallerFormClosing(object sender, FormClosingEventArgs e)
        {
            if (!running)
            {
                return;
            }
            e.Cancel = true;
            MessageBox.Show(this, "安装或卸载正在执行，请等待操作完成。", Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        private void BrowseButtonClick(object sender, EventArgs e)
        {
            using (FolderBrowserDialog dialog = new FolderBrowserDialog())
            {
                dialog.Description = "选择 Steam common 下的 Octopath_Traveler2 文件夹";
                dialog.ShowNewFolderButton = false;
                if (Directory.Exists(gameRootTextBox.Text))
                {
                    dialog.SelectedPath = gameRootTextBox.Text;
                }
                if (dialog.ShowDialog(this) == DialogResult.OK)
                {
                    gameRootTextBox.Text = dialog.SelectedPath;
                    statusLabel.Text = "目录已选择";
                }
            }
        }

        private void RunInstallerScript(string scriptName, string actionName)
        {
            if (running)
            {
                return;
            }

            string gameRoot;
            try
            {
                gameRoot = Path.GetFullPath(gameRootTextBox.Text.Trim()).TrimEnd(Path.DirectorySeparatorChar);
            }
            catch
            {
                ShowInputError("请选择有效的游戏目录。");
                return;
            }

            string gameExecutable = Path.Combine(
                gameRoot,
                "Octopath_Traveler2",
                "Binaries",
                "Win64",
                "Octopath_Traveler2-Win64-Shipping.exe");
            if (!File.Exists(gameExecutable))
            {
                ShowInputError("所选目录中没有找到游戏主程序。请选择 Steam common 下的 Octopath_Traveler2 文件夹。");
                return;
            }

            string scriptPath = Path.Combine(packageRoot, "scripts", scriptName);
            if (!File.Exists(scriptPath))
            {
                ShowInputError("安装器旁缺少 scripts 文件夹。请保留完整的 Mod 文件夹结构。");
                return;
            }

            string powershellPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                "WindowsPowerShell",
                "v1.0",
                "powershell.exe");
            if (!File.Exists(powershellPath))
            {
                powershellPath = "powershell.exe";
            }

            running = true;
            SetControlsEnabled(false);
            statusLabel.ForeColor = SystemColors.ControlText;
            statusLabel.Text = actionName + "中……";
            outputTextBox.Clear();
            AppendOutput("游戏目录：" + gameRoot + Environment.NewLine);
            AppendOutput("正在执行" + actionName + "……" + Environment.NewLine + Environment.NewLine);

            Thread worker = new Thread(delegate()
            {
                int exitCode = -1;
                string standardOutput = string.Empty;
                string standardError = string.Empty;
                Exception failure = null;

                try
                {
                    ProcessStartInfo startInfo = new ProcessStartInfo();
                    startInfo.FileName = powershellPath;
                    startInfo.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File "
                        + QuoteArgument(scriptPath)
                        + " -GameRoot "
                        + QuoteArgument(gameRoot);
                    startInfo.WorkingDirectory = packageRoot;
                    startInfo.UseShellExecute = false;
                    startInfo.CreateNoWindow = true;
                    startInfo.RedirectStandardOutput = true;
                    startInfo.RedirectStandardError = true;

                    using (Process process = new Process())
                    {
                        process.StartInfo = startInfo;
                        process.Start();
                        standardOutput = process.StandardOutput.ReadToEnd();
                        standardError = process.StandardError.ReadToEnd();
                        process.WaitForExit();
                        exitCode = process.ExitCode;
                    }
                }
                catch (Exception exception)
                {
                    failure = exception;
                }

                BeginInvoke(new Action(delegate
                {
                    if (!string.IsNullOrWhiteSpace(standardOutput))
                    {
                        AppendOutput(standardOutput.TrimEnd() + Environment.NewLine);
                    }
                    if (!string.IsNullOrWhiteSpace(standardError))
                    {
                        AppendOutput(Environment.NewLine + standardError.TrimEnd() + Environment.NewLine);
                    }
                    if (failure != null)
                    {
                        AppendOutput(Environment.NewLine + failure.Message + Environment.NewLine);
                    }

                    bool success = failure == null && exitCode == 0;
                    statusLabel.ForeColor = success ? Color.DarkGreen : Color.DarkRed;
                    statusLabel.Text = success ? actionName + "完成" : actionName + "失败";
                    AppendOutput(Environment.NewLine + statusLabel.Text + "。" + Environment.NewLine);
                    running = false;
                    SetControlsEnabled(true);

                    MessageBox.Show(
                        this,
                        success ? actionName + "已经完成。" : actionName + "执行失败，请查看窗口中的输出。",
                        Text,
                        MessageBoxButtons.OK,
                        success ? MessageBoxIcon.Information : MessageBoxIcon.Error);
                }));
            });
            worker.IsBackground = true;
            worker.Start();
        }

        private static string QuoteArgument(string value)
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }

        private void ShowInputError(string message)
        {
            statusLabel.ForeColor = Color.DarkRed;
            statusLabel.Text = message;
            MessageBox.Show(this, message, Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }

        private void SetControlsEnabled(bool enabled)
        {
            gameRootTextBox.Enabled = enabled;
            browseButton.Enabled = enabled;
            installButton.Enabled = enabled;
            uninstallButton.Enabled = enabled;
        }

        private void AppendOutput(string text)
        {
            outputTextBox.AppendText(text);
            outputTextBox.SelectionStart = outputTextBox.TextLength;
            outputTextBox.ScrollToCaret();
        }
    }
}
