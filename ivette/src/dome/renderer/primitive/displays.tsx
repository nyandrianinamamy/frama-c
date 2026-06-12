/* ************************************************************************ */
/*                                                                          */
/*   SPDX-License-Identifier LGPL-2.1                                       */
/*   Copyright (C)                                                          */
/*   CEA (Commissariat à l'énergie atomique et aux énergies alternatives)   */
/*                                                                          */
/* ************************************************************************ */

// --------------------------------------------------------------------------
// --- LEDs, LCD, meters, etc.
// --------------------------------------------------------------------------

/**
   @packageDocumentation
   @module dome/primitive/displays
 */

import React, { LegacyRef } from 'react';
import { classes } from 'dome/misc/utils';
import { ColorKind } from 'dome/primitive/colors';
import Gallery from './gallery.json';
import './style.css';

/* @ internal */
const Icons: { [id: string]: { viewBox?: string; path: string } } = Gallery;

// --------------------------------------------------------------------------
// --- Raw SVG element
// --------------------------------------------------------------------------

// export type string = keyof typeof Gallery;
export interface SVGprops {
  /** Icon's identifier. */
  id: string;
  /** Icon's tool-tip. */
  title?: string;
  /** Icon's dimension in pixels (default: `12`). */
  size?: number;
  /** Additional class name(s). */
  className?: string;
  /**  */
  fill?: string;
}

/**
   Low-level SVG icon.
   Only returns the identified `<svg/>` element from Icon base.
 */
export function SVG(props: SVGprops): null | JSX.Element {
  const { id, className, fill } = props;
  const icon = Icons[id];
  if (!icon) return <>{id}</>;
  const {
    title,
    size = 12,
  } = props;
  const { path, viewBox = '0 0 24 24' } = icon;
  return (
    <svg style={{ height: size }} viewBox={viewBox} className={className} >
      {title && <title>{title}</title>}
      <path d={path} fill={fill} />
    </svg>
  );
}

// --------------------------------------------------------------------------
// --- Icon Component
// --------------------------------------------------------------------------

/** Icon Component Properties */
export interface IconProps extends SVGprops {
  /** Additional class name(s). */
  className?: string;
  /** Display (default is true). */
  display?: boolean;
  /** Visibility (default is true). */
  visible?: boolean;
  /** Additional DIV style. */
  style?: React.CSSProperties;
  /** Styled icon */
  kind?: ColorKind;
  /** On mouse enter */
  onMouseEnter?: (event: React.MouseEvent<HTMLDivElement>) => void;
  /** On mouse leave */
  onMouseLeave?: (event: React.MouseEvent<HTMLDivElement>) => void;
}

/**
   Icon Component.
   Consult the [Icon Gallery](../../doc/guides/icons.md) for default icons.
 */
export function Icon(props: IconProps): JSX.Element {
  const {
    id, title, kind='default',
    size, className, style,
    visible = true, display = true,
    onMouseEnter, onMouseLeave
  } = props;
  const divClass = classes(
    'dome-xIcon',
    `dome-xIcon-${kind}`,
    !visible && 'dome-control-hidden',
    !display && 'dome-control-erased',
    id === "SPINNER" && 'dome-xIcon-spinning',
    className
  );

  return (
    <div
      className={divClass}
      style={style}
      onMouseEnter={onMouseEnter}
      onMouseLeave={onMouseLeave}
    >
      <SVG id={id} size={size} title={title} />
    </div>
  );
}


// --------------------------------------------------------------------------
// --- Icon Database
// --------------------------------------------------------------------------

/** Custom Icon Properties */
export interface CustomIcon {
  /** Icon identifier. */
  id: string;
  /** Icon's viewBox (default is `"0 0 24 24"`). */
  viewBox?: string;
  /** Icon's SVG path. */
  path: string;
}

/**
   Register a new custom icon.
 */
export function register(icon: CustomIcon): void {
  const { id, ...jsicon } = icon;
  Icons[id] = jsicon;
}

export interface IconData extends CustomIcon {
  section?: string;
  title?: string;
}

/**
   Iterate over icons gallery.
   See [[register]] to add custom icons to the gallery.
 */
export function forEach(fn: (ico: IconData) => void): void {
  const ids = Object.keys(Icons);
  ids.forEach((id) => {
    const jsicon = Icons[id];
    fn({ id, ...jsicon });
  });
}


// --------------------------------------------------------------------------
// --- Led
// --------------------------------------------------------------------------

export const LEDStatusList = [
  'active', 'inactive', 'positive', 'negative', 'warning'
] as const;

export type LEDstatus = typeof LEDStatusList[number] | undefined;

export function jLEDstatus(js : string) : LEDstatus {
  return LEDStatusList.find(elt => elt === js);
}

export interface LEDprops {
  /**
     Led status:
     - `'inactive'`: off (default)
     - `'active'`: blue color
     - `'positive'`: green color
     - `'negative'`: red color
     - `'warning'`: orange color
   */
  status?: LEDstatus;
  /** Blinking Led (default: `false`). */
  blink?: boolean;
  /** Tooltip text. */
  title?: string;
  /** Additional CSS class. */
  className?: string;
  /** Additional CSS style. */
  style?: React.CSSProperties;
}

export const LED = (props: LEDprops): JSX.Element => {
  const className = classes(
    'dome-xButton-led',
    `dome-xButton-led-${props.status || 'inactive'}`,
    props.blink && 'dome-xButton-blink',
    props.className,
  );
  return (
    <div className={className} title={props.title} style={props.style} />
  );
};

// --------------------------------------------------------------------------
// --- Metter
// --------------------------------------------------------------------------

export interface MeterProps {
  /** Additional CSS class. */
  className?: string;
  /** Additional CSS style. */
  style?: React.CSSProperties;
  /** Disabled control. */
  /** Meter value. Undefined means disabled. */
  value: number; /** default is undefined */
  min?: number;  /** default is 0.0 */
  low?: number;  /** default is 0.0 */
  high?: number; /** default is 1.0 */
  max?: number;  /** default is 1.0 */
  optimum?: number | 'LOW' | 'MEDIUM' | 'HIGH'; /** default is undefined */
}

export const Meter = (props: MeterProps): JSX.Element => {
  const { className, style, value, optimum, ...ms } = props;
  const min = props.min ?? 0.0;
  const max = props.max ?? 1.0;
  const low = props.low ?? min;
  const high = props.high ?? max;
  const theClass = classes('dome-xMeter', className);
  let opt: number | undefined;
  if (value !== undefined)
    switch (optimum) {
      case 'LOW': opt = (min + low) / 2; break;
      case 'MEDIUM': opt = (low + high) / 2; break;
      case 'HIGH': opt = (high + max) / 2; break;
      default: opt = optimum;
    }
  const mv = value === undefined ? min : Math.min(max, Math.max(min, value));
  return (
    <meter
      className={theClass}
      style={style}
      value={mv}
      optimum={opt}
      {...ms} />
  );
};

// --------------------------------------------------------------------------
// --- Generic Label
// --------------------------------------------------------------------------

/** Labels support forwarding refs to their inner [<label/>] element. */
export interface LabelProps {
  /** Text of the label. Prepend to other children elements. */
  label?: string;
  /** Tool-tip description. */
  title?: string;
  /** Icon identifier. Displayed on the left side of the label. */
  icon?: string;
  /** Additional class for icon. */
  iconClassName?: string;
  /** Icon kind. */
  kind?: ColorKind,
  /** Additional class. */
  className?: string;
  /** Additional style. */
  style?: React.CSSProperties;
  /** If `false`, do not display the label. Default to `true`. */
  display?: boolean;
  /** Additional content of the `<label/>` element. */
  children?: React.ReactNode;
  /** Html tag `<input />` element. */
  htmlFor?: string;
  /** Click event callback. */
  onDoubleClick?: (evt: React.MouseEvent) => void;
  /** Right-click event callback. */
  onContextMenu?: (evt: React.MouseEvent) => void;
}

const makeLabel = (className: string) =>
  function Label(
    props: LabelProps,
    ref: LegacyRef<HTMLLabelElement> | undefined
  ): JSX.Element {
    const { display = true, kind = 'default' } = props;
    const allClasses = classes(
      className,
      !display && 'dome-control-erased',
      props.className,
    );
    const iconClass = classes(
      'dome-xIcon-' + kind,
      props.iconClassName,
    );
    return (
      <label
        ref={ref}
        className={allClasses}
        title={props.title}
        style={props.style}
        onDoubleClick={props.onDoubleClick}
        onContextMenu={props.onContextMenu}
        htmlFor={props.htmlFor}
      >
        {props.icon &&
          <Icon title={props.title}
                id={props.icon}
                className={iconClass}
          />}
        {props.label}
        {props.children}
      </label>
    );
  };

// --------------------------------------------------------------------------
// --- CSS Classes
// --------------------------------------------------------------------------

const LABEL = 'dome-xLabel dome-text-label';
const TITLE = 'dome-xLabel dome-text-title';
const DESCR = 'dome-xLabel dome-text-descr';
const TDATA = 'dome-xLabel dome-text-data';
const TCODE = 'dome-xLabel dome-text-code';
const TCELL = 'dome-xLabel dome-text-cell';
const TITEM = 'dome-xLabel dome-text-item';

// --------------------------------------------------------------------------
// --- Components
// --------------------------------------------------------------------------

/** Simple labels. */
export const Label = React.forwardRef(makeLabel(LABEL));

/** Title and headings. */
export const Title = React.forwardRef(makeLabel(TITLE));

/** Description, textbook content. */
export const Descr = React.forwardRef(makeLabel(DESCR));

/** Selectable textual information. */
export const Data = React.forwardRef(makeLabel(TDATA));

/** Selectable inlined source-code content. */
export const Code = React.forwardRef(makeLabel(TCODE));

/** Selectable inlined source-code content with default cursor. */
export const Cell = React.forwardRef(makeLabel(TCELL));

/** Non-selectable inlined source-code content with default cursor. */
export const Item = React.forwardRef(makeLabel(TITEM));


// --------------------------------------------------------------------------
// --- LCD
// --------------------------------------------------------------------------

/** label in a button style. */
export function LCD(props: LabelProps): JSX.Element {
  const className = classes('dome-xLCD ', props.className);
  return <Code {...props} className={className} />;
}

// --------------------------------------------------------------------------
// ---  Badge Component
// --------------------------------------------------------------------------

/** Label in a badge style. */
export function Badge(props: LabelProps): JSX.Element {
  const className = classes('dome-xBadge ', props.className);
  return <Label {...props} className={className} />;
}

// --------------------------------------------------------------------------
