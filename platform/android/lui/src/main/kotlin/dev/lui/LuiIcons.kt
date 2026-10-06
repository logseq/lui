package dev.lui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.*
import androidx.compose.material.icons.rounded.*
import androidx.compose.ui.graphics.vector.ImageVector

/** Maps LUI built-in icon names (schema/components.json's icon vocabulary)
 * to Material symbols. `app:<name>` icons resolve through the host's
 * registered app-icon table first. */
object LuiIcons {
    private val registered = mutableMapOf<String, ImageVector>()

    /** Hosts register their own `app:<name>` icon assets here. */
    fun registerAppIcon(name: String, icon: ImageVector) {
        registered[name] = icon
    }

    fun appIcon(name: String): ImageVector? = registered[name]

    fun resolve(name: String): ImageVector {
        if (name.startsWith("app:")) {
            return registered[name.substring(4)] ?: Icons.Rounded.HelpOutline
        }
        return when (name) {
            "alert" -> Icons.Rounded.Warning
            "archive" -> Icons.Rounded.Archive
            "arrow-down" -> Icons.Rounded.ArrowDownward
            "arrow-right" -> Icons.AutoMirrored.Rounded.ArrowForward
            "arrow-up" -> Icons.Rounded.ArrowUpward
            "check" -> Icons.Rounded.Check
            "check-circle" -> Icons.Rounded.CheckCircle
            "chevron-down" -> Icons.Rounded.KeyboardArrowDown
            "chevron-left" -> Icons.AutoMirrored.Rounded.KeyboardArrowLeft
            "chevron-right" -> Icons.AutoMirrored.Rounded.KeyboardArrowRight
            "chevron-up" -> Icons.Rounded.KeyboardArrowUp
            "circle-dot" -> Icons.Rounded.Adjust
            "clock" -> Icons.Rounded.Schedule
            "copy" -> Icons.Rounded.ContentCopy
            "download" -> Icons.Rounded.Download
            "edit" -> Icons.Rounded.Edit
            "ellipsis" -> Icons.Rounded.MoreHoriz
            "external-link" -> Icons.Rounded.OpenInNew
            "eye" -> Icons.Rounded.Visibility
            "file-text" -> Icons.Rounded.Description
            "folder" -> Icons.Rounded.Folder
            "folder-open" -> Icons.Rounded.FolderOpen
            "git-branch" -> Icons.Rounded.AccountTree
            "git-merge" -> Icons.Rounded.Merge
            "git-pull-request" -> Icons.Rounded.CallMerge
            "info" -> Icons.Rounded.Info
            "menu" -> Icons.Rounded.Menu
            "mic" -> Icons.Rounded.Mic
            "moon" -> Icons.Rounded.DarkMode
            "music" -> Icons.Rounded.MusicNote
            "panel-left" -> Icons.AutoMirrored.Rounded.ViewSidebar
            "panel-right" -> Icons.AutoMirrored.Rounded.ViewSidebar
            "pause" -> Icons.Rounded.Pause
            "play" -> Icons.Rounded.PlayArrow
            "plus" -> Icons.Rounded.Add
            "refresh-cw" -> Icons.Rounded.Refresh
            "repeat" -> Icons.Rounded.Repeat
            "save" -> Icons.Rounded.Save
            "search" -> Icons.Rounded.Search
            "send" -> Icons.AutoMirrored.Rounded.Send
            "settings" -> Icons.Rounded.Settings
            "shuffle" -> Icons.Rounded.Shuffle
            "skip-back" -> Icons.Rounded.SkipPrevious
            "skip-forward" -> Icons.Rounded.SkipNext
            "sun" -> Icons.Rounded.LightMode
            "terminal" -> Icons.Rounded.Terminal
            "trash" -> Icons.Rounded.Delete
            "volume" -> Icons.Rounded.VolumeUp
            "wrench" -> Icons.Rounded.Build
            "x" -> Icons.Rounded.Close
            "x-circle" -> Icons.Rounded.Cancel
            else -> Icons.Rounded.HelpOutline
        }
    }
}
