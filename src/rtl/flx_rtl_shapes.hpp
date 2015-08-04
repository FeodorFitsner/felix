#ifndef __FLX_RTL_SHAPES_HPP__
#define __FLX_RTL_SHAPES_HPP__
#include "flx_rtl_config.hpp"
#include "flx_gc.hpp"

namespace flx { namespace rtl {
// ********************************************************
// Shape (RTTI) objects for system classes
// con_t is only an abstract base, so has no fixed shape
// shapes for instance types generated by Felix compiler
// we provide a shape for C 'int' type as well
// ********************************************************

// special: just the offset data for a pointer
RTL_EXTERN extern ::flx::gc::generic::offset_data_t const _address_offset_data;

RTL_EXTERN extern ::flx::gc::generic::gc_shape_t _fthread_ptr_map;
RTL_EXTERN extern ::flx::gc::generic::gc_shape_t schannel_ptr_map;
RTL_EXTERN extern ::flx::gc::generic::gc_shape_t _uctor_ptr_map;
RTL_EXTERN extern ::flx::gc::generic::gc_shape_t _int_ptr_map;
RTL_EXTERN extern ::flx::gc::generic::gc_shape_t cl_t_ptr_map;
RTL_EXTERN extern ::flx::gc::generic::gc_shape_t _address_ptr_map;
//RTL_EXTERN extern ::flx::gc::generic::gc_shape_t _caddress_ptr_map;
RTL_EXTERN extern ::flx::gc::generic::gc_shape_t slist_node_ptr_map;
RTL_EXTERN extern ::flx::gc::generic::gc_shape_t slist_ptr_map;
RTL_EXTERN extern ::flx::gc::generic::gc_shape_t flx_dynlink_ptr_map;
RTL_EXTERN extern ::flx::gc::generic::gc_shape_t flx_libinst_ptr_map;

}}
#endif

