// MainViewModel.kt -- This file is part of tiny_container.
//
// Copyright (C) 2026 Caten Hu
//
// Tiny Container is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License,
// or any later version.
//
// Tiny Container is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty
// of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see http://www.gnu.org/licenses/.

package com.fct.tc4.ui.main

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class MainViewModel(application: Application) : AndroidViewModel(application) {
    private val _screen = MutableStateFlow<Screen>(Screen.Init)
    val screen: StateFlow<Screen> = _screen.asStateFlow()

    fun navigateTo(target: Screen) {
        viewModelScope.launch {
            _screen.value = target
        }
    }

    sealed class Screen {
        data object Init : Screen()
        data object ContainerManage : Screen()
        data class ContainerInstall(val code: String, val webpage: String?) : Screen()
        data class ContainerMain(val code: String) : Screen()
        /** First step of the on-device distro/DE build flow — pick a base distro. */
        data object DistroSelect : Screen()
        /** Second step — pick a desktop environment for the [distroAlias] chosen in DistroSelect. */
        data class DeSelect(val distroAlias: String) : Screen()
    }


    private val _isTerminalOpen = MutableStateFlow(false)
    val isTerminalOpen: StateFlow<Boolean> = _isTerminalOpen.asStateFlow()

    fun toggleTerminal() {
        _isTerminalOpen.value = !_isTerminalOpen.value
    }

    fun closeTerminal() {
        _isTerminalOpen.value = false
    }

    // ================ 待执行的捷径命令（内存临时态） ================

    companion object {
        /**
         * 桌面捷径启动时，如果容器未运行，先暂存命令，
         * 等 ContainerMainViewModel 初始化完成后发送。
         */
        @Volatile
        var pendingCommandCode: String? = null

        @Volatile
        var pendingCommandText: String? = null

        fun clearPendingCommand() {
            pendingCommandCode = null
            pendingCommandText = null
        }
    }
}
