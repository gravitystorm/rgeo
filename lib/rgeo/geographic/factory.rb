# -----------------------------------------------------------------------------
# 
# Geographic data factory implementation
# 
# -----------------------------------------------------------------------------
# Copyright 2010 Daniel Azuma
# 
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# * Neither the name of the copyright holder, nor the names of any other
#   contributors to this software, may be used to endorse or promote products
#   derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
# -----------------------------------------------------------------------------
;


module RGeo
  
  module Geographic
    
    
    # This class implements the various factories for geography features.
    # See methods of the RGeo::Geographic module for the API for creating
    # geography factories.
    
    class Factory
      
      include Feature::Factory::Instance
      
      
      def initialize(impl_prefix_, opts_={})  # :nodoc:
        @impl_prefix = impl_prefix_
        @point_class = Geographic.const_get("#{impl_prefix_}PointImpl")
        @line_string_class = Geographic.const_get("#{impl_prefix_}LineStringImpl")
        @linear_ring_class = Geographic.const_get("#{impl_prefix_}LinearRingImpl")
        @line_class = Geographic.const_get("#{impl_prefix_}LineImpl")
        @polygon_class = Geographic.const_get("#{impl_prefix_}PolygonImpl")
        @geometry_collection_class = Geographic.const_get("#{impl_prefix_}GeometryCollectionImpl")
        @multi_point_class = Geographic.const_get("#{impl_prefix_}MultiPointImpl")
        @multi_line_string_class = Geographic.const_get("#{impl_prefix_}MultiLineStringImpl")
        @multi_polygon_class = Geographic.const_get("#{impl_prefix_}MultiPolygonImpl")
        @support_z = opts_[:has_z_coordinate] ? true : false
        @support_m = opts_[:has_m_coordinate] ? true : false
        @srid = opts_[:srid] || 4326
        @proj4 = opts_[:proj4]
        if CoordSys::Proj4.supported?
          if @proj4.kind_of?(::String) || @proj4.kind_of?(::Hash)
            @proj4 = CoordSys::Proj4.create(@proj4)
          end
        else
          @proj4 = nil
        end
        @coord_sys = opts_[:coord_sys]
        if @coord_sys.kind_of?(::String)
          @coord_sys = CoordSys::CS.create_from_wkt(@coord_sys) rescue nil
        end
        
        wkt_generator_ = opts_[:wkt_generator]
        case wkt_generator_
        when ::Hash
          @wkt_generator = WKRep::WKTGenerator.new(wkt_generator_)
        else
          @wkt_generator = WKRep::WKTGenerator.new(:convert_case => :upper)
        end
        wkb_generator_ = opts_[:wkb_generator]
        case wkb_generator_
        when ::Hash
          @wkb_generator = WKRep::WKBGenerator.new(wkb_generator_)
        else
          @wkb_generator = WKRep::WKBGenerator.new
        end
        wkt_parser_ = opts_[:wkt_parser]
        case wkt_parser_
        when ::Hash
          @wkt_parser = WKRep::WKTParser.new(self, wkt_parser_)
        else
          @wkt_parser = WKRep::WKTParser.new(self)
        end
        wkb_parser_ = opts_[:wkb_parser]
        case wkb_parser_
        when ::Hash
          @wkb_parser = WKRep::WKBParser.new(self, wkb_parser_)
        else
          @wkb_parser = WKRep::WKBParser.new(self)
        end
      end
      
      
      def _set_projector(projector_)  # :nodoc:
        @projector = projector_
      end
      
      
      # Equivalence test.
      
      def eql?(rhs_)
        rhs_.is_a?(Geographic::Factory) &&
          @impl_prefix == rhs_.instance_variable_get(:@impl_prefix) &&
          @support_z == rhs_.instance_variable_get(:@support_z) &&
          @support_m == rhs_.instance_variable_get(:@support_m) &&
          @proj4 == rhs_.instance_variable_get(:@proj4)
      end
      alias_method :==, :eql?
      
      
      # Returns the srid reported by this factory.
      
      def srid
        @srid
      end
      
      
      # Returns true if this factory supports a projection.
      
      def has_projection?
        !@projector.nil?
      end
      
      
      # Returns the factory for the projected coordinate space,
      # or nil if this factory does not support a projection.
      
      def projection_factory
        @projector ? @projector.projection_factory : nil
      end
      
      
      # Projects the given geometry into the projected coordinate space,
      # and returns the projected geometry.
      # Returns nil if this factory does not support a projection.
      # Raises Error::InvalidGeometry if the given geometry is not of
      # this factory.
      
      def project(geometry_)
        return nil unless @projector
        unless geometry_.factory == self
          raise Error::InvalidGeometry, 'Wrong geometry type'
        end
        @projector.project(geometry_)
      end
      
      
      # Reverse-projects the given geometry from the projected coordinate
      # space into lat-long space.
      # Raises Error::InvalidGeometry if the given geometry is not of
      # the projection defined by this factory.
      
      def unproject(geometry_)
        unless @projector && @projector.projection_factory == geometry_.factory
          raise Error::InvalidGeometry, 'You can unproject only features that are in the projected coordinate space.'
        end
        @projector.unproject(geometry_)
      end
      
      
      # Returns true if this factory supports a projection and the
      # projection wraps its x (easting) direction. For example, a
      # Mercator projection wraps, but a local projection that is valid
      # only for a small area does not wrap. Returns nil if this factory
      # does not support or a projection, or if it is not known whether
      # or not it wraps.
      
      def projection_wraps?
        @projector ? @projector.wraps? : nil
      end
      
      
      # Returns a ProjectedWindow specifying the limits of the domain of
      # the projection space.
      # Returns nil if this factory does not support a projection, or the
      # projection limits are not known.
      
      def projection_limits_window
        if @projector
          unless defined?(@projection_limits_window)
            @projection_limits_window = @projector.limits_window
          end
          @projection_limits_window
        else
          nil
        end
      end
      
      
      # See ::RGeo::Feature::Factory#property
      
      def property(name_)
        case name_
        when :has_z_coordinate
          @support_z
        when :has_m_coordinate
          @support_m
        when :is_geographic
          true
        else
          nil
        end
      end
      
      
      # See ::RGeo::Feature::Factory#parse_wkt
      
      def parse_wkt(str_)
        @wkt_parser.parse(str_)
      end
      
      
      # See ::RGeo::Feature::Factory#parse_wkb
      
      def parse_wkb(str_)
        @wkb_parser.parse(str_)
      end
      
      
      # See ::RGeo::Feature::Factory#point
      
      def point(x_, y_, *extra_)
        @point_class.new(self, x_, y_, *extra_) rescue nil
      end
      
      
      # See ::RGeo::Feature::Factory#line_string
      
      def line_string(points_)
        @line_string_class.new(self, points_) rescue nil
      end
      
      
      # See ::RGeo::Feature::Factory#line
      
      def line(start_, end_)
        @line_class.new(self, start_, end_) rescue nil
      end
      
      
      # See ::RGeo::Feature::Factory#linear_ring
      
      def linear_ring(points_)
        @linear_ring_class.new(self, points_) rescue nil
      end
      
      
      # See ::RGeo::Feature::Factory#polygon
      
      def polygon(outer_ring_, inner_rings_=nil)
        @polygon_class.new(self, outer_ring_, inner_rings_) rescue nil
      end
      
      
      # See ::RGeo::Feature::Factory#collection
      
      def collection(elems_)
        @geometry_collection_class.new(self, elems_) rescue nil
      end
      
      
      # See ::RGeo::Feature::Factory#multi_point
      
      def multi_point(elems_)
        @multi_point_class.new(self, elems_) rescue nil
      end
      
      
      # See ::RGeo::Feature::Factory#multi_line_string
      
      def multi_line_string(elems_)
        @multi_line_string_class.new(self, elems_) rescue nil
      end
      
      
      # See ::RGeo::Feature::Factory#multi_polygon
      
      def multi_polygon(elems_)
        @multi_polygon_class.new(self, elems_) rescue nil
      end
      
      
      # See ::RGeo::Feature::Factory#proj4
      
      def proj4
        @proj4
      end
      
      
      # See ::RGeo::Feature::Factory#coord_sys
      
      def coord_sys
        @coord_sys
      end
      
      
    end
    
  end
  
end
