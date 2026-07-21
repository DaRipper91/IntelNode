// DeSelectFragment.kt -- This file is part of tiny_container.
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

package com.fct.tc4.ui.page

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.fragment.app.activityViewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.fct.tc4.R
import com.fct.tc4.databinding.Tc4FragmentDeSelectBinding
import com.fct.tc4.databinding.Tc4ItemDeBinding
import com.fct.tc4.databinding.Tc4ItemDeSectionHeaderBinding
import com.fct.tc4.ui.main.MainViewModel
import com.fct.tc4.ui.misc.ConfirmInstallDialogFragment
import com.fct.tc4.ui.misc.DeEntry
import com.fct.tc4.ui.misc.DeTier
import com.fct.tc4.ui.misc.DistroEntry
import com.fct.tc4.ui.misc.ProgressDialogFragment
import com.google.android.material.snackbar.Snackbar
import kotlinx.coroutines.launch

/**
 * Stage 2 of the on-device build flow — pick a DE (or none, for a
 * command-line-only container) for the distro chosen in DistroSelectFragment,
 * confirm a container code, then run the build via [DistroBuildViewModel].
 */
class DeSelectFragment : Fragment() {

    private var _binding: Tc4FragmentDeSelectBinding? = null
    private val binding get() = _binding!!

    private val mainViewModel: MainViewModel by activityViewModels()
    private val buildViewModel: DistroBuildViewModel by activityViewModels()

    private val distroAlias: String by lazy { requireArguments().getString(ARG_DISTRO_ALIAS)!! }
    private val distro: DistroEntry by lazy {
        buildViewModel.distroByAlias(distroAlias)
            ?: error("Unknown distro alias reached DeSelectFragment: $distroAlias")
    }

    override fun onResume() {
        super.onResume()
        requireActivity().title = getString(R.string.tc4_de_select_title)
    }

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?
    ): View {
        _binding = Tc4FragmentDeSelectBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        val adapter = DeAdapter(
            isSelectable = { de -> buildViewModel.isSelectable(de, distro) },
            onClick = { de -> onDeChosen(de) },
        )
        binding.recyclerView.layoutManager = LinearLayoutManager(requireContext())
        binding.recyclerView.adapter = adapter

        val items = buildList {
            add(DeListItem.SkipOption)
            add(DeListItem.Header(getString(R.string.tc4_de_tier1_header)))
            buildViewModel.tier1Des.forEach { add(DeListItem.De(it)) }
            if (buildViewModel.tier2Des.isNotEmpty()) {
                add(DeListItem.Header(getString(R.string.tc4_de_tier2_header)))
                buildViewModel.tier2Des.forEach { add(DeListItem.De(it)) }
            }
        }
        adapter.submitList(items)

        childFragmentManager.setFragmentResultListener(REQUEST_CONFIRM_CODE, viewLifecycleOwner) { _, bundle ->
            if (!bundle.getBoolean(ConfirmInstallDialogFragment.KEY_CONFIRMED)) return@setFragmentResultListener
            val code = bundle.getString(ConfirmInstallDialogFragment.KEY_CODE) ?: return@setFragmentResultListener
            val de = pendingDe
            startBuildProgressObserver()
            buildViewModel.startBuild(distro, de, code)
        }

        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                buildViewModel.buildState.collect { state ->
                    when (state) {
                        is DistroBuildViewModel.BuildState.Idle -> Unit
                        is DistroBuildViewModel.BuildState.Progress -> {
                            getOrShowProgressDialog()?.updateTitle(state.message)
                        }
                        is DistroBuildViewModel.BuildState.Completed -> {
                            (childFragmentManager.findFragmentByTag(PROGRESS_TAG) as? ProgressDialogFragment)?.dismiss()
                            buildViewModel.resetBuildState()
                            mainViewModel.navigateTo(MainViewModel.Screen.ContainerManage)
                        }
                        is DistroBuildViewModel.BuildState.Failed -> {
                            (childFragmentManager.findFragmentByTag(PROGRESS_TAG) as? ProgressDialogFragment)?.dismiss()
                            buildViewModel.resetBuildState()
                            Snackbar.make(binding.root, getString(R.string.tc4_build_failed, state.message), Snackbar.LENGTH_LONG).show()
                        }
                    }
                }
            }
        }
    }

    private var pendingDe: DeEntry? = null

    private fun onDeChosen(de: DeEntry?) {
        if (de != null && !buildViewModel.isSelectable(de, distro)) return
        pendingDe = de
        ConfirmInstallDialogFragment.show(
            childFragmentManager,
            REQUEST_CONFIRM_CODE,
            initialCode = distro.alias,
            name = de?.let { "${distro.displayName} (${it.displayName})" } ?: distro.displayName,
            description = "",
        )
    }

    private fun getOrShowProgressDialog(): ProgressDialogFragment? {
        (childFragmentManager.findFragmentByTag(PROGRESS_TAG) as? ProgressDialogFragment)?.let { return it }
        return ProgressDialogFragment.newBuilder(childFragmentManager).show(PROGRESS_TAG)
    }

    private fun startBuildProgressObserver() {
        getOrShowProgressDialog()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    companion object {
        private const val ARG_DISTRO_ALIAS = "distro_alias"
        private const val REQUEST_CONFIRM_CODE = "de_select_confirm_code"
        private const val PROGRESS_TAG = "de_select_build_progress"

        fun newInstance(distroAlias: String): DeSelectFragment = DeSelectFragment().apply {
            arguments = Bundle().apply { putString(ARG_DISTRO_ALIAS, distroAlias) }
        }
    }
}

private sealed interface DeListItem {
    data class Header(val title: String) : DeListItem
    data object SkipOption : DeListItem
    data class De(val entry: DeEntry) : DeListItem
}

private class DeAdapter(
    private val isSelectable: (DeEntry) -> Boolean,
    private val onClick: (DeEntry?) -> Unit,
) : ListAdapter<DeListItem, RecyclerView.ViewHolder>(DIFF_CALLBACK) {

    companion object {
        private const val TYPE_HEADER = 0
        private const val TYPE_SKIP = 1
        private const val TYPE_DE = 2

        private val DIFF_CALLBACK = object : DiffUtil.ItemCallback<DeListItem>() {
            override fun areItemsTheSame(old: DeListItem, new: DeListItem) = when {
                old is DeListItem.Header && new is DeListItem.Header -> old.title == new.title
                old is DeListItem.SkipOption && new is DeListItem.SkipOption -> true
                old is DeListItem.De && new is DeListItem.De -> old.entry.alias == new.entry.alias
                else -> false
            }
            override fun areContentsTheSame(old: DeListItem, new: DeListItem) = old == new
        }
    }

    override fun getItemViewType(position: Int): Int = when (getItem(position)) {
        is DeListItem.Header -> TYPE_HEADER
        is DeListItem.SkipOption -> TYPE_SKIP
        is DeListItem.De -> TYPE_DE
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        val inflater = LayoutInflater.from(parent.context)
        return when (viewType) {
            TYPE_HEADER -> HeaderVH(Tc4ItemDeSectionHeaderBinding.inflate(inflater, parent, false))
            TYPE_SKIP, TYPE_DE -> DeVH(Tc4ItemDeBinding.inflate(inflater, parent, false), isSelectable, onClick)
            else -> error("unknown view type: $viewType")
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        when (val item = getItem(position)) {
            is DeListItem.Header -> (holder as HeaderVH).bind(item)
            is DeListItem.SkipOption -> (holder as DeVH).bindSkip()
            is DeListItem.De -> (holder as DeVH).bind(item.entry)
        }
    }

    class HeaderVH(private val binding: Tc4ItemDeSectionHeaderBinding) : RecyclerView.ViewHolder(binding.root) {
        fun bind(header: DeListItem.Header) {
            binding.headerText.text = header.title
        }
    }

    class DeVH(
        private val binding: Tc4ItemDeBinding,
        private val isSelectable: (DeEntry) -> Boolean,
        private val onClick: (DeEntry?) -> Unit,
    ) : RecyclerView.ViewHolder(binding.root) {
        fun bindSkip() {
            binding.name.text = binding.root.context.getString(R.string.tc4_de_skip)
            binding.status.visibility = View.GONE
            binding.tierBadge.visibility = View.GONE
            binding.itemCard.setOnClickListener { onClick(null) }
        }

        fun bind(de: DeEntry) {
            binding.name.text = de.displayName
            binding.tierBadge.visibility =
                if (de.tier == DeTier.EXPERIMENTAL) View.VISIBLE else View.GONE
            val available = isSelectable(de)
            binding.status.visibility = if (available) View.GONE else View.VISIBLE
            binding.status.text = binding.root.context.getString(R.string.tc4_de_status_unavailable)
            binding.itemCard.isEnabled = available
            binding.itemCard.alpha = if (available) 1f else 0.5f
            binding.itemCard.setOnClickListener { if (available) onClick(de) }
        }
    }
}
