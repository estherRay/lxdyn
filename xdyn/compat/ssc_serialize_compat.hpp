// xdyn-side libc++ compatibility shim for SSC's SerializeMapsSetsAndVectors.hpp (Hazard D).
//
// SSC keys its std::vector/map/set/pair operator<< off libstdc++-internal include guards
// (_GLIBCXX_VECTOR/_MAP/_SET/_STL_PAIR_H). Under libc++ those are never defined, so the operators
// silently vanish. We define them *only* across the SSC include, then undef before anything else
// (notably Eigen's StlSupport/StdVector.h, which reads the same macro to pick a libstdc++-only path)
// can see them. SSC is NOT modified. A no-op under libstdc++.
//
// Force-include this (-include) ahead of the SSC serializer in the 2 consumers
// (mesh/MeshIntersector.cpp, mesh/ClosingFacetComputer.cpp).
#ifndef XDYN_SSC_SERIALIZE_COMPAT_HPP
#define XDYN_SSC_SERIALIZE_COMPAT_HPP

// Pull the real STL headers in first, so defining the guards below cannot suppress them.
#include <vector>
#include <map>
#include <set>
#include <utility>
#include <list>

// Hazard G — libc++ behavioural gap. SSC's ssc::data_source::coerce(list<double>&,
// const vector<T>&) iterates the vector and recurses on *it. For vector<bool>,
// libstdc++ yields a plain `bool` (matches the arithmetic overload) but libc++
// yields a proxy `__bit_const_reference`, which matches nothing → "no matching
// function for call to 'coerce'". Inject a bool overload (the proxy converts to
// bool) *before* TypeCoercion.hpp is included, so its templates see it at phase-1
// lookup. SSC is NOT modified; harmless under libstdc++ (non-template preferred
// over the arithmetic template for a real bool, so no ambiguity).
namespace ssc { namespace data_source {
    inline void coerce(std::list<double>& ret, bool b) { ret.push_back(b ? 1.0 : 0.0); }
}}

#if defined(_LIBCPP_VERSION)
#  ifndef _GLIBCXX_VECTOR
#    define _GLIBCXX_VECTOR
#    define XDYN_SHIM_GLIBCXX_VECTOR
#  endif
#  ifndef _GLIBCXX_MAP
#    define _GLIBCXX_MAP
#    define XDYN_SHIM_GLIBCXX_MAP
#  endif
#  ifndef _GLIBCXX_SET
#    define _GLIBCXX_SET
#    define XDYN_SHIM_GLIBCXX_SET
#  endif
#  ifndef _STL_PAIR_H
#    define _STL_PAIR_H
#    define XDYN_SHIM_STL_PAIR_H
#  endif
#endif

#include <ssc/macros/SerializeMapsSetsAndVectors.hpp>

#if defined(_LIBCPP_VERSION)
#  ifdef XDYN_SHIM_GLIBCXX_VECTOR
#    undef _GLIBCXX_VECTOR
#    undef XDYN_SHIM_GLIBCXX_VECTOR
#  endif
#  ifdef XDYN_SHIM_GLIBCXX_MAP
#    undef _GLIBCXX_MAP
#    undef XDYN_SHIM_GLIBCXX_MAP
#  endif
#  ifdef XDYN_SHIM_GLIBCXX_SET
#    undef _GLIBCXX_SET
#    undef XDYN_SHIM_GLIBCXX_SET
#  endif
#  ifdef XDYN_SHIM_STL_PAIR_H
#    undef _STL_PAIR_H
#    undef XDYN_SHIM_STL_PAIR_H
#  endif
#endif

#endif // XDYN_SSC_SERIALIZE_COMPAT_HPP
