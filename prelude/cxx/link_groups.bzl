# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under both the MIT license found in the
# LICENSE-MIT file in the root directory of this source tree and the Apache
# License, Version 2.0 found in the LICENSE-APACHE file in the root directory
# of this source tree.

load(
    "@prelude//linking:link_info.bzl",
    "LinkArgs",
    "LinkInfo",  # @unused Used as a type
    "LinkInfos",  # @unused Used as a type
    "LinkStyle",
    "Linkage",
    "LinkedObject",  # @unused Used as a type
    "get_actual_link_style",
    get_link_info_from_link_infos = "get_link_info",
)
load(
    "@prelude//linking:linkable_graph.bzl",
    "LinkableNode",  # @unused Used as a type
    "get_link_info",
    "linkable_deps",
)
load(
    "@prelude//utils:dicts.bzl",
    "merge_x",
)
load(
    "@prelude//utils:graph_utils.bzl",
    "breadth_first_traversal_by",
)
load(
    "@prelude//utils:utils.bzl",
    "expect",
)
load(
    ":groups.bzl",
    "Group",  # @unused Used as a type
    "MATCH_ALL_LABEL",
    "NO_MATCH_LABEL",
)
load(
    ":link.bzl",
    "cxx_link_shared_library",
)

LINK_GROUP_MAP_DATABASE_SUB_TARGET = "link-group-map-database"
LINK_GROUP_MAP_FILE_NAME = "link_group_map.json"

LinkGroupInfo = provider(fields = [
    "groups",  # [Group.type]
    "groups_hash",  # str.type
    "mappings",  # {"label": str.type}
])

LinkGroupLinkInfo = record(
    link_info = field(LinkInfo.type),
    link_style = field(LinkStyle.type),
)

# Information about a linkable node which explicitly sets `link_group`.
LinkGroupLib = record(
    # The label of the owning target (if any).
    label = field(["label", None], None),
    # The shared libs to package for this link group.
    shared_libs = field({str.type: LinkedObject.type}),
    # The link info to link against this link group.
    shared_link_infos = field(LinkInfos.type),
)

# Provider propagating info about transitive link group libs.
_LinkGroupLibInfo = provider(fields = [
    # A map of link group names to their shared libraries.
    "libs",  # {str.type: _LinkGroupLib.type}
])

LinkGroupLibSpec = record(
    # The output name given to the linked shared object.
    name = field(str.type),
    # Used to differentiate normal native shared libs from e.g. Python native
    # extensions (which are techncially shared libs, but don't set a SONAME
    # and aren't managed by `SharedLibraryInfo`s).
    is_shared_lib = field(bool.type, True),
    # The link group to link.
    group = field(Group.type),
)

def gather_link_group_libs(
        libs: {str.type: LinkGroupLib.type} = {},
        deps: ["dependency"] = []) -> {str.type: LinkGroupLib.type}:
    """
    Return all link groups libs deps and top-level libs.
    """
    libs = dict(libs)
    for dep in deps:
        dep_info = dep.get(_LinkGroupLibInfo)
        if dep_info != None:
            merge_x(
                libs,
                dep_info.libs,
                fmt = "conflicting link group roots for \"{0}\": {1} != {2}",
            )
    return libs

def merge_link_group_lib_info(
        label: "label",
        name: [str.type, None] = None,
        shared_libs: [{str.type: LinkedObject.type}, None] = None,
        shared_link_infos: [LinkInfos.type, None] = None,
        deps: ["dependency"] = []) -> _LinkGroupLibInfo.type:
    """
    Merge and return link group info libs from deps and the current rule wrapped
    in a provider.
    """
    libs = {}
    if name != None:
        libs[name] = LinkGroupLib(
            label = label,
            shared_libs = shared_libs,
            shared_link_infos = shared_link_infos,
        )
    return _LinkGroupLibInfo(
        libs = gather_link_group_libs(
            libs = libs,
            deps = deps,
        ),
    )

def get_link_group(ctx: "context") -> [str.type, None]:
    return ctx.attrs.link_group

def get_link_group_info(ctx: "context") -> [LinkGroupInfo.type, None]:
    """
    Parses the currently analyzed context for any link group definitions
    and returns a list of all link groups with their mappings.
    """
    link_group_map = ctx.attrs.link_group_map

    if not link_group_map:
        return None

    if type(link_group_map) == "dependency":
        return link_group_map[LinkGroupInfo]

    fail("Link group maps must be provided as a link_group_map rule dependency.")

def get_auto_link_group_libs(ctx: "context") -> [{str.type: LinkGroupLib.type}, None]:
    """
    Return link group libs created by the link group map rule.
    """
    link_group_map = ctx.attrs.link_group_map

    if not link_group_map:
        return None

    if type(link_group_map) == "dependency":
        info = link_group_map.get(_LinkGroupLibInfo)
        if info == None:
            return None
        return info.libs

    fail("Link group maps must be provided as a link_group_map rule dependency.")

def get_link_group_preferred_linkage(link_groups: [Group.type]) -> {"label": Linkage.type}:
    return {
        mapping.target.label: mapping.preferred_linkage
        for group in link_groups
        for mapping in group.mappings
        if mapping.preferred_linkage != None
    }

def get_filtered_labels_to_links_map(
        linkable_graph_node_map: {"label": LinkableNode.type},
        link_group: [str.type, None],
        link_group_mappings: [{"label": str.type}, None],
        link_group_preferred_linkage: {"label": Linkage.type},
        link_style: LinkStyle.type,
        deps: ["dependency"],
        link_group_libs: {str.type: LinkGroupLib.type} = {},
        prefer_stripped: bool.type = False,
        is_executable_link: bool.type = False) -> {"label": LinkGroupLinkInfo.type}:
    """
    Given a linkable graph, link style and link group mappings, finds all links
    to consider for linking traversing the graph as necessary and then
    identifies which link infos and targets belong the in the provided link group.
    If no link group is provided, all unmatched link infos are returned.
    """

    deps = linkable_deps(deps)

    def get_traversed_deps(node: "label") -> ["label"]:
        linkable_node = linkable_graph_node_map[node]  # buildifier: disable=uninitialized

        # Always link against exported deps
        node_linkables = list(linkable_node.exported_deps)

        # If the preferred linkage is `static` or `any` with a link style that is
        # not shared, we need to link against the deps too.
        should_traverse = False
        if linkable_node.preferred_linkage == Linkage("static"):
            should_traverse = True
        elif linkable_node.preferred_linkage == Linkage("any"):
            should_traverse = link_style != Linkage("shared")

        if should_traverse:
            node_linkables += linkable_node.deps

        return node_linkables

    # Get all potential linkable targets
    linkables = breadth_first_traversal_by(
        linkable_graph_node_map,
        deps,
        get_traversed_deps,
    )

    # An index of target to link group names, for all link group library nodes.
    # Provides fast lookup of a link group root lib via it's label.
    link_group_roots = {
        lib.label: name
        for name, lib in link_group_libs.items()
        if lib.label != None
    }

    linkable_map = {}

    # Keep track of whether we've already added a link group to the link line
    # already.  This avoids use adding the same link group lib multiple times,
    # for each of the possible multiple nodes that maps to it.
    link_group_added = {}

    def add_link(target: "label", link_style: LinkStyle.type):
        linkable_map[target] = LinkGroupLinkInfo(
            link_info = get_link_info(linkable_graph_node_map[target], link_style, prefer_stripped),
            link_style = link_style,
        )  # buildifier: disable=uninitialized

    def add_link_group(target: "label", target_group: str.type):
        # If we've already added this link group to the link line, we're done.
        if target_group in link_group_added:
            return

        # In some flows, we may not have access to the actual link group lib
        # in our dep tree (e.g. https://fburl.com/code/pddmkptb), so just bail
        # in this case.
        # NOTE(agallagher): This case seems broken, as we're not going to set
        # DT_NEEDED tag correctly, or detect missing syms at link time.
        link_group_lib = link_group_libs.get(target_group)
        if link_group_lib == None:
            return

        expect(target_group != link_group)
        link_group_added[target_group] = None
        linkable_map[target] = LinkGroupLinkInfo(
            link_info = get_link_info_from_link_infos(link_group_lib.shared_link_infos),
            link_style = LinkStyle("shared"),
        )  # buildifier: disable=uninitialized

    for target in linkables:
        node = linkable_graph_node_map[target]
        actual_link_style = get_actual_link_style(link_style, link_group_preferred_linkage.get(target, node.preferred_linkage))

        # Always link any shared dependencies
        if actual_link_style == LinkStyle("shared"):
            # If this target is a link group root library, we
            # 1) don't propagate shared linkage down the tree, and
            # 2) use the provided link info in lieu of what's in the grph.
            target_link_group = link_group_roots.get(target)
            if target_link_group != None and target_link_group != link_group:
                add_link_group(target, target_link_group)
            else:
                add_link(target, LinkStyle("shared"))

                # Mark transitive deps as shared.
                for exported_dep in node.exported_deps:
                    exported_node = linkable_graph_node_map[exported_dep]
                    if exported_node.preferred_linkage == Linkage("any"):
                        link_group_preferred_linkage[exported_dep] = Linkage("shared")
        else:  # static or static_pic
            target_link_group = link_group_mappings.get(target)

            if not target_link_group and not link_group:
                # Ungrouped linkable targets belong to the unlabeled executable
                add_link(target, actual_link_style)
            elif is_executable_link and target_link_group == NO_MATCH_LABEL:
                # Targets labeled NO_MATCH belong to the unlabeled executable
                add_link(target, actual_link_style)
            elif target_link_group == MATCH_ALL_LABEL or target_link_group == link_group:
                # If this belongs to the match all link group or the group currently being evaluated
                add_link(target, actual_link_style)
            elif target_link_group not in (None, NO_MATCH_LABEL, MATCH_ALL_LABEL):
                add_link_group(target, target_link_group)

    return linkable_map

def get_filtered_links(labels_to_links_map: {"label": LinkGroupLinkInfo.type}):
    return [link_group_info.link_info for link_group_info in labels_to_links_map.values()]

def get_filtered_targets(labels_to_links_map: {"label": LinkGroupLinkInfo.type}):
    return [label.raw_target() for label in labels_to_links_map.keys()]

def get_link_group_map_json(ctx: "context", targets: ["target_label"]) -> DefaultInfo.type:
    json_map = ctx.actions.write_json(LINK_GROUP_MAP_FILE_NAME, sorted(targets))
    return DefaultInfo(default_outputs = [json_map])

def create_link_group(
        ctx: "context",
        spec: LinkGroupLibSpec.type,
        linkable_graph_node_map: {"label": LinkableNode.type} = {},
        linker_flags: [""] = [],
        link_group_mappings: {"label": str.type} = {},
        link_group_preferred_linkage: {"label": Linkage.type} = {},
        link_style: LinkStyle.type = LinkStyle("static_pic"),
        link_group_libs: {str.type: LinkGroupLib.type} = {},
        prefer_stripped_objects: bool.type = False,
        prefer_local: bool.type = False,
        category_suffix: [str.type, None] = None) -> LinkedObject.type:
    """
    Link a link group library, described by a `LinkGroupLibSpec`.  This is
    intended to handle regular shared libs and e.g. Python extensions.
    """

    inputs = []

    # Add extra linker flags.
    if linker_flags:
        inputs.append(LinkInfo(pre_flags = linker_flags))

    # Add roots...
    filtered_labels_to_links_map = get_filtered_labels_to_links_map(
        linkable_graph_node_map,
        spec.group.name,
        link_group_mappings,
        link_group_preferred_linkage,
        link_group_libs = link_group_libs,
        link_style = link_style,
        deps = [mapping.target for mapping in spec.group.mappings],
        is_executable_link = False,
        prefer_stripped = prefer_stripped_objects,
    )
    inputs.extend(get_filtered_links(filtered_labels_to_links_map))

    # link the rule
    return cxx_link_shared_library(
        ctx,
        ctx.actions.declare_output(spec.name),
        name = spec.name if spec.is_shared_lib else None,
        links = [LinkArgs(infos = inputs)],
        category_suffix = category_suffix,
        identifier = spec.name,
        prefer_local = prefer_local,
    )
