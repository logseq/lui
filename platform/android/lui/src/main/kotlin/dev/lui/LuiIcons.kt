package dev.lui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.CallMerge
import androidx.compose.material.icons.automirrored.filled.HelpOutline
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.*
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * Resolves the wire `icon` prop (a symbolic name such as "send" or
 * "chevron-right") to an ImageVector. Apps chain their own resolver in
 * front of [DEFAULT] via [or] — the backend resolver returns null for
 * names it doesn't own (e.g. `app:`-prefixed app icons) so they fall
 * through to the next resolver.
 */
fun interface LuiIconResolver {
    fun icon(name: String): ImageVector?

    fun or(other: LuiIconResolver): LuiIconResolver = LuiIconResolver { name ->
        icon(name) ?: other.icon(name)
    }

    companion object {
        val DEFAULT = LuiIconResolver { name -> defaultIcons[name] }

        private val defaultIcons: Map<String, ImageVector> = mapOf(
            "add" to Icons.Filled.Add,
            "add-circle" to Icons.Filled.AddCircle,
            "alert" to Icons.Filled.Warning,
            "arrow-back" to Icons.AutoMirrored.Filled.ArrowBack,
            "arrow-down" to Icons.Filled.ArrowDropDown,
            "arrow-forward" to Icons.AutoMirrored.Filled.ArrowForward,
            "arrow-left" to Icons.AutoMirrored.Filled.ArrowBack,
            "arrow-right" to Icons.AutoMirrored.Filled.ArrowForward,
            "arrow-up" to Icons.Filled.KeyboardArrowUp,
            "attach-file" to Icons.Filled.Add,
            "audio-lines" to Icons.Filled.Star,
            "audio-waveform" to Icons.Filled.Star,
            "bell" to Icons.Filled.Notifications,
            "bold" to Icons.Filled.Edit,
            "bookmark" to Icons.Filled.Bookmark,
            "brush" to Icons.Filled.Edit,
            "calendar" to Icons.Filled.DateRange,
            "camera" to Icons.Filled.Add,
            "check" to Icons.Filled.Check,
            "check-circle" to Icons.Filled.CheckCircle,
            "chevron-down" to Icons.Filled.KeyboardArrowDown,
            "chevron-left" to Icons.AutoMirrored.Filled.KeyboardArrowLeft,
            "chevron-right" to Icons.AutoMirrored.Filled.KeyboardArrowRight,
            "chevron-up" to Icons.Filled.KeyboardArrowUp,
            "clock" to Icons.Filled.Star,
            "close" to Icons.Filled.Close,
            "cloud" to Icons.Filled.Star,
            "code" to Icons.Filled.Edit,
            "copy" to Icons.Filled.Add,
            "dice" to Icons.Filled.Star,
            "dots" to Icons.Filled.MoreVert,
            "download" to Icons.Filled.Share,
            "edit" to Icons.Filled.Edit,
            "external-link" to Icons.Filled.Share,
            "eye" to Icons.Filled.Star,
            "file" to Icons.Filled.Add,
            "flag" to Icons.Filled.Star,
            "folder" to Icons.Filled.Star,
            "hash" to Icons.Filled.Tag,
            "heading" to Icons.Filled.Edit,
            "help" to Icons.AutoMirrored.Filled.HelpOutline,
            "history" to Icons.Filled.Star,
            "home" to Icons.Filled.Home,
            "image" to Icons.Filled.Star,
            "info" to Icons.Filled.Info,
            "italic" to Icons.Filled.Edit,
            "link" to Icons.Filled.Share,
            "list" to Icons.Filled.List,
            "loader" to Icons.Filled.Refresh,
            "lock" to Icons.Filled.Lock,
            "logout" to Icons.Filled.ExitToApp,
            "menu" to Icons.Filled.Menu,
            "merge" to Icons.AutoMirrored.Filled.CallMerge,
            "message" to Icons.Filled.Email,
            "mic" to Icons.Filled.Edit,
            "minus" to Icons.Filled.Clear,
            "more-horizontal" to Icons.Filled.MoreVert,
            "more-vertical" to Icons.Filled.MoreVert,
            "paperclip" to Icons.Filled.Add,
            "pause" to Icons.Filled.Star,
            "pencil" to Icons.Filled.Edit,
            "play" to Icons.Filled.PlayArrow,
            "plus" to Icons.Filled.Add,
            "refresh" to Icons.Filled.Refresh,
            "search" to Icons.Filled.Search,
            "send" to Icons.AutoMirrored.Filled.Send,
            "settings" to Icons.Filled.Settings,
            "share" to Icons.Filled.Share,
            "sparkles" to Icons.Filled.Star,
            "star" to Icons.Filled.Star,
            "stop" to Icons.Filled.Close,
            "sync" to Icons.Filled.Refresh,
            "table" to Icons.Filled.List,
            "tag" to Icons.Filled.Tag,
            "task" to Icons.Filled.CheckCircle,
            "trash" to Icons.Filled.Delete,
            "undo" to Icons.AutoMirrored.Filled.Undo,
            "upload" to Icons.Filled.Share,
            "user" to Icons.Filled.Person,
            "video" to Icons.Filled.PlayArrow,
            "warning" to Icons.Filled.Warning,
            "wifi" to Icons.Filled.Star,
            "x" to Icons.Filled.Close,
        )
    }
}
