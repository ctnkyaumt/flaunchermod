import 'package:flutter/material.dart';

/// Vertical cut-off (in logical pixels) below which a focus node is considered
/// page content rather than an AppBar action.
const double appBarBottom = 100;

/// Implemented by the widget state that owns the vertical page view, so the
/// traversal policy can hand off a directional move that runs off the edge of
/// the current page.
abstract class PageNavigationHandler {
  /// Returns `true` when the move was consumed by switching pages.
  bool handlePageNavigation(TraversalDirection direction, FocusNode currentNode);
}

class NodeSearcher {
  final TraversalDirection directionToSearch;

  NodeSearcher(this.directionToSearch);

  /// should be called first
  List<FocusNode> findCandidates(List<FocusNode> nodes, FocusNode from) {
    switch (directionToSearch) {
      case TraversalDirection.up:
        return nodes.where((element) => !element.isBelowOrEquals(from)).toList();
      case TraversalDirection.down:
        return nodes.where((element) => !element.isAboveOrEquals(from)).toList();
      case TraversalDirection.right:
        return nodes
            .where((element) => !element.isLeftToOrEquals(from) && element.isOnTheSameRow(from))
            .toList();
      case TraversalDirection.left:
        return nodes
            .where((element) => !element.isRightToOrEquals(from) && element.isOnTheSameRow(from))
            .toList();
    }
  }

  FocusNode findBestFocusNode(List<FocusNode> candidates, FocusNode from) {
    return candidates.reduce((bestNode, challenger) {
      if (directionToSearch == TraversalDirection.down && challenger.isAbove(bestNode)) {
        return challenger;
      } else if (directionToSearch == TraversalDirection.up && challenger.isBelow(bestNode)) {
        return challenger;
      } else if (directionToSearch == TraversalDirection.left && challenger.isRightTo(bestNode)) {
        return challenger;
      } else if (directionToSearch == TraversalDirection.right && challenger.isLeftTo(bestNode)) {
        return challenger;
      }
      // compute the element which is the closest horizontally
      if (challenger.isOnTheSameRow(bestNode) &&
          challenger.squaredDistance(from) < bestNode.squaredDistance(from)) {
        return challenger;
      }
      return bestNode;
    });
  }
}

/// A few extension methods to the [FocusNode] to be able to compare their
/// respective position easily.
extension Geometry on FocusNode {
  bool isBelow(FocusNode other) {
    return rect.center.dy.round() > other.rect.center.dy.round();
  }

  bool isBelowOrEquals(FocusNode other) {
    return rect.center.dy.round() >= other.rect.center.dy.round();
  }

  bool isRightTo(FocusNode other) {
    return rect.center.dx.round() > other.rect.center.dx.round();
  }

  bool isRightToOrEquals(FocusNode other) {
    return rect.center.dx.round() >= other.rect.center.dx.round();
  }

  bool isLeftTo(FocusNode other) {
    return rect.center.dx.round() < other.rect.center.dx.round();
  }

  bool isLeftToOrEquals(FocusNode other) {
    return rect.center.dx.round() <= other.rect.center.dx.round();
  }

  bool isAbove(FocusNode other) {
    return rect.center.dy.round() < other.rect.center.dy.round();
  }

  bool isAboveOrEquals(FocusNode other) {
    return rect.center.dy.round() <= other.rect.center.dy.round();
  }

  bool isOnTheSameRow(FocusNode other) {
    // Use a tolerance of 5 pixels to account for slight vertical differences
    // in horizontal scrollable lists where items might not be perfectly aligned
    return (rect.center.dy.round() - other.rect.center.dy.round()).abs() <= 5;
  }

  /// Squared euclidean distance — only ever used for comparisons, so the
  /// square root would be wasted work on every directional key press.
  double squaredDistance(FocusNode other) {
    final dx = rect.center.dx - other.rect.center.dx;
    final dy = rect.center.dy - other.rect.center.dy;
    return dx * dx + dy * dy;
  }
}

/// Custom traversal policy that handles page navigation at boundaries
class PageAwareTraversalPolicy extends FocusTraversalPolicy with DirectionalFocusTraversalPolicyMixin {
  final PageNavigationHandler handler;

  PageAwareTraversalPolicy(this.handler);

  @override
  Iterable<FocusNode> sortDescendants(Iterable<FocusNode> descendants, FocusNode currentNode) => descendants;

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    List<FocusNode>? nodes = currentNode.nearestScope?.traversalDescendants.toList();
    if (nodes == null) {
      return super.inDirection(currentNode, direction);
    }

    // For left/right navigation, implement infinite loop cycling within the same row
    if (direction == TraversalDirection.left || direction == TraversalDirection.right) {
      List<FocusNode> sameRowNodes = nodes.where((node) => node.isOnTheSameRow(currentNode)).toList();
      
      if (sameRowNodes.length > 1) {
        sameRowNodes.sort((a, b) => a.rect.center.dx.compareTo(b.rect.center.dx));
        
        int currentIndex = sameRowNodes.indexWhere((node) => node == currentNode);
        if (currentIndex != -1) {
          final nextNode = direction == TraversalDirection.right
              ? sameRowNodes[(currentIndex + 1) % sameRowNodes.length]
              : sameRowNodes[(currentIndex - 1 + sameRowNodes.length) % sameRowNodes.length];
          nextNode.requestFocus();
          return true;
        }
      }
      
      return true;
    }

    // For up/down navigation, check if we're at a boundary
    NodeSearcher searcher = NodeSearcher(direction);
    List<FocusNode> candidates = searcher.findCandidates(nodes, currentNode);

    // If no candidates found, we're at a boundary - trigger page navigation
    if (candidates.isEmpty) {
      handler.handlePageNavigation(direction, currentNode);
      return true;
    }

    FocusNode nextNode = searcher.findBestFocusNode(candidates, currentNode);

    // When moving UP from page content, skip focusing AppBar actions; treat as a boundary
    // so one press can move between pages.
    if (direction == TraversalDirection.up) {
      final fromContent = currentNode.rect.center.dy > appBarBottom;
      final toAppBar = nextNode.rect.center.dy <= appBarBottom;
      // If not handled (e.g. we are on the first page), fall through to the AppBar.
      if (fromContent && toAppBar && handler.handlePageNavigation(direction, currentNode)) {
        return true;
      }
    }

    nextNode.requestFocus();
    return true;
  }
}
