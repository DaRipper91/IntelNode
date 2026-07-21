// DistroSelectFragment.kt -- This file is part of tiny_container.
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
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.fct.tc4.R
import com.fct.tc4.databinding.Tc4FragmentDistroSelectBinding
import com.fct.tc4.databinding.Tc4ItemDistroBinding
import com.fct.tc4.ui.main.MainViewModel
import com.fct.tc4.ui.misc.DistroEntry

/** Stage 1 of the on-device build flow — pick a base distro. See DeSelectFragment for stage 2. */
class DistroSelectFragment : Fragment() {

    private var _binding: Tc4FragmentDistroSelectBinding? = null
    private val binding get() = _binding!!

    private val mainViewModel: MainViewModel by activityViewModels()
    private val buildViewModel: DistroBuildViewModel by activityViewModels()

    override fun onResume() {
        super.onResume()
        requireActivity().title = getString(R.string.tc4_distro_select_title)
    }

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?
    ): View {
        _binding = Tc4FragmentDistroSelectBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        val adapter = DistroAdapter { distro ->
            mainViewModel.navigateTo(MainViewModel.Screen.DeSelect(distro.alias))
        }
        binding.recyclerView.layoutManager = LinearLayoutManager(requireContext())
        binding.recyclerView.adapter = adapter
        adapter.submitList(buildViewModel.distros)
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}

private class DistroAdapter(
    private val onClick: (DistroEntry) -> Unit,
) : ListAdapter<DistroEntry, DistroAdapter.ViewHolder>(DIFF_CALLBACK) {

    companion object {
        private val DIFF_CALLBACK = object : DiffUtil.ItemCallback<DistroEntry>() {
            override fun areItemsTheSame(old: DistroEntry, new: DistroEntry) = old.alias == new.alias
            override fun areContentsTheSame(old: DistroEntry, new: DistroEntry) = old == new
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val binding = Tc4ItemDistroBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return ViewHolder(binding, onClick)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    class ViewHolder(
        private val binding: Tc4ItemDistroBinding,
        private val onClick: (DistroEntry) -> Unit,
    ) : RecyclerView.ViewHolder(binding.root) {
        fun bind(distro: DistroEntry) {
            binding.name.text = distro.displayName
            binding.packageManager.text = distro.packageManager.name.lowercase()
            binding.itemCard.setOnClickListener { onClick(distro) }
        }
    }
}
