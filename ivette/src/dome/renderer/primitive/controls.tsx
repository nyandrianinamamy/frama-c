/* ************************************************************************ */
/*                                                                          */
/*   SPDX-License-Identifier LGPL-2.1                                       */
/*   Copyright (C)                                                          */
/*   CEA (Commissariat à l'énergie atomique et aux énergies alternatives)   */
/*                                                                          */
/* ************************************************************************ */

/**
 * This file contains basic components designed to perform an action
 *
 * a BaseButton component (unexported) and its variants
 * - Button
 * - CircButton
 * - TextButton
 * - IconButton
 * - Checkbox
 * - Radio
 * - Switch
 *
 * a ButtonGroup component and 2 variants
 * - MultiChoiceGroup (to group the checkboxes, ....)
 * - SingleChoiceGroup (to group the radioButtons, ....)
 *
 * and
 * - Spinner
 * - Field
 * - Select
 */

// --------------------------------------------------------------------------

/**
   @packageDocumentation
   @module dome/primitive/buttons
*/

import React, { LegacyRef } from 'react';
import { classes } from 'dome/misc/utils';
import { ColorKind } from 'dome/primitive/colors';
import { Icon } from './displays';
import './style.css';


// --------------------------------------------------------------------------
// --- Button
// --------------------------------------------------------------------------

export type TypeValue = number | string | boolean | undefined
export type OnEvent<A = TypeValue> = (evt:React.MouseEvent, value?: A) => void
type Selected = boolean | ((v: TypeValue) => boolean)


function isButtonSelected(value: TypeValue, selected?: Selected): boolean {
  return selected && typeof selected === 'function' ?
    selected(value) : !!selected;
}

export interface BaseButtonProps {
  ref?: LegacyRef<HTMLButtonElement>
  /** Text of the label. Prepend to other children elements. */
  label?: string;
  /** Icon identifier. Displayed on the left side of the label. */
  icon?: string;
  /** Icon color: fill. */
  color?: string;
  /** Icon size */
  size?: number;
  /** Tool-tip description. */
  title?: string;
  /** Additional class. */
  className?: string;
  /** Additional style. */
  style?: React.CSSProperties;
  /** Defaults to `false`. */
  disabled?: boolean;
  /** Defaults to `true`. */
  visible?: boolean;
  /** Defaults to `true`. */
  display?: boolean;
  /**
     May gain focus.
     Focused button can be clicked with the `ENTER` key.
     Defaults to `false`.
   */
  focusable?: boolean;
  /** Color kind */
  kind?: ColorKind;
  /** Display a background. Default to `false` */
  noBackground?: boolean;
  /** Blinking button. Defaults to `false`. */
  blink?: boolean;
  /** value assigned to the button */
  value?: TypeValue,
  /**
   * Indicates whether the button is selected.
   * Can be a fixed boolean value or a function evaluated dynamically
   * to determine the current selection state.
   */
  selected?: Selected;
  /**
     Button callback.
     An undefined callback automatically disables the button.
   */
  onClick?: OnEvent;
  /** Right-Click callback. Receives the button's value. */
  onContextMenu?: OnEvent;
  /** Callback for other mouse button click. Receives the button's value. */
  onAuxClick?: OnEvent;
  /** Click event callback. */
  onDoubleClick?: (evt: React.MouseEvent) => void;
}

/** Base button. */
function BaseButton(props: BaseButtonProps): JSX.Element {
  const {
    value, color,
    focusable = false, kind = 'default',
    visible = true, display = true, blink = false,
    selected, icon, size, label, className = '',
    noBackground = false, onContextMenu, onAuxClick
  } = props;

  const disabled = props.onClick ? props.disabled : true;
  const isSelected = isButtonSelected(value, selected);

  const theClass = classes(
    'dome-xButton',
    `dome-xButton-${kind}`,
    blink && 'dome-xButton-blink',
    noBackground && 'dome-xButton-no-background',
    isSelected && 'dome-control-selected',
    disabled && 'dome-control-disabled',
    !visible && 'dome-control-hidden',
    !display && 'dome-control-erased',
    className,
  );
  const nofocus = focusable ? undefined : true;

  const getIconKind = (): ColorKind | undefined =>
    noBackground ? kind : undefined;

  const onButtonClick = (evt: React.MouseEvent): void => {
    evt?.stopPropagation();
    props.onClick?.(evt, value);
  };

  return (
    <button
      ref={props.ref}
      type="button"
      className={theClass}
      disabled={disabled}
      onClick={onButtonClick}
      onDoubleClick={props.onDoubleClick}
      onContextMenu={onContextMenu && ((evt) => onContextMenu(evt, value))}
      onAuxClick={onAuxClick && ((evt) => onAuxClick(evt, value))}
      title={props.title}
      style={props.style}
      tabIndex={nofocus && -1}
      onMouseDown={nofocus && ((evt) => evt.preventDefault())}
    >
      {icon &&
        <Icon id={icon} size={size} kind={getIconKind()} fill={color}/>
      }
      {label && <div>{label}</div>}
    </button>
  );
}

// --------------------------------------------------------------------------
// --- Standard Button
// --------------------------------------------------------------------------

export function Button(props: BaseButtonProps): JSX.Element {
  const theClass = classes('dome-xBoxButton',  props.className);
  return <BaseButton {...props} value={props.value} className={theClass} />;
}

// --------------------------------------------------------------------------
// --- Circ Button
// --------------------------------------------------------------------------

export function CircButton(props: Omit<BaseButtonProps, 'label'>)
: JSX.Element {
  const theClass = classes('dome-xCircButton',  props.className);
  return <BaseButton {...props} className={theClass} />;
}

// --------------------------------------------------------------------------
// --- Text Button => button without background
// --------------------------------------------------------------------------

export function TextButton(props: BaseButtonProps): JSX.Element {
  return <BaseButton {...props} noBackground={true} />;
}

// --------------------------------------------------------------------------
// --- Icon Button
// --------------------------------------------------------------------------

export interface IconButtonProps extends
  Omit<BaseButtonProps, 'label' | 'value' | 'icon' > { icon: string; }

/** Borderless Icon Button. Label property is ignored. */
export function IconButton(props: IconButtonProps): JSX.Element | null {
  const theClass = classes('dome-xIconButton', props.className);
  return <BaseButton {...props} icon={props.icon}
      className={theClass} noBackground={true} />;
}

// --------------------------------------------------------------------------
// --- On/Off Button
// --------------------------------------------------------------------------

interface OnOffButtonProps extends  Omit<BaseButtonProps, 'icon'> {
  icon: 'CHECKBOX' | 'RADIO' | 'SWITCH',
  typeClass: string
}

function OnOffButton(props: OnOffButtonProps): JSX.Element {
  const { value, selected, icon, typeClass } = props;
  const className = classes(typeClass, props.className);
  const iconId = isButtonSelected(value, selected) ? icon+'.ON' : icon+'.OFF';
  return <BaseButton {...props}
    icon={iconId} noBackground={true} className={className}/>;
}

// --- CheckBox Button
export function Checkbox(props: Omit<BaseButtonProps, 'icon'>): JSX.Element {
  return <OnOffButton {...props} typeClass='dome-xCheckbox' icon='CHECKBOX'/>;
}

// --- Radio Button
export function Radio(props: Omit<BaseButtonProps, 'icon'>): JSX.Element {
  return <OnOffButton {...props} typeClass='dome-xRadio' icon='RADIO' />;
}

// --- Switch Button
export function Switch(props: Omit<BaseButtonProps, 'icon'>): JSX.Element {
  return <OnOffButton {...props} typeClass='dome-xSwitch' icon='SWITCH' />;
}

// --------------------------------------------------------------------------
// --- Button groups single and multiple choice
// --------------------------------------------------------------------------

interface ButtonGroupProps {
  /** vertical separation between buttons. default to true*/
  separate?: boolean;
  /** Disabled Group (default `false`). */
  disabled?: boolean;
  /** Displayed vertically */
  vertical?: boolean
  /** Additional class. */
  className?: string;
  /** Additional style. */
  style?: React.CSSProperties;
  /** Buttons array. */
  children: React.JSX.Element[];
  /**
   * Indicates whether the button is selected.
   * Can be a fixed boolean value or a function evaluated dynamically
   * to determine the current selection state.
   */
  isSelected?: Selected,
  /** Callback on clicked on a button */
  onGroupChanged?: OnEvent,
}

/**
   Properties of the button group are passed down the buttons of the group
   as appropriate defaults.
 */
export function ButtonGroup(props: ButtonGroupProps): JSX.Element {
  const { separate = false, onGroupChanged, isSelected,
    children, vertical = false } = props;

  const baseButtonProps: BaseButtonProps = {};
  if(isSelected) baseButtonProps.selected = isSelected;
  if(onGroupChanged) baseButtonProps.onClick = onGroupChanged;
  if(props.disabled) baseButtonProps.disabled = true;

  const className = classes(
    'dome-xButtongroup',
    separate && 'dome-xButtongroup-separate',
    vertical && 'dome-xButtongroup-vertical',
    props.className
  );

  return (
    <div className={className} style={props.style}>
      {React.Children.map(children, (elt) => React.cloneElement(
        elt,
        {  ...elt.props, ...baseButtonProps },
      ))}
    </div>
  );
}

/** Button Group with multiple choices like CheckboxGroup */
export interface SingleChoiceGroupProps
  extends Omit<ButtonGroupProps, 'isSelected' | 'onGroupChanged'> {
  /** Currently selected button. */
  value?: TypeValue;
  /** Callback on clicked buttons. */
  onChange?: (v: TypeValue) => void;
}

export function SingleChoiceGroup(props: SingleChoiceGroupProps): JSX.Element {
  const { children, value, onChange } = props;

  const state = React.useState<TypeValue>(value);
  const [groupValue, setGroupValue] = state;
  const onGroupChanged = React.useCallback(
    (_e: React.MouseEvent, val: TypeValue): void => {
      setGroupValue(val);
  }, [setGroupValue]);

  React.useEffect(() => {
    if(onChange) onChange(groupValue);
  }, [onChange, groupValue]);

  return (
    <ButtonGroup {...props}
      isSelected={(a) => groupValue === a}
      onGroupChanged={onGroupChanged}
    >{children}</ButtonGroup>
  );
}

/** Button Group with a single choice like CheckboxGroup */
export interface MultiChoiceGroupProps
  extends Omit<ButtonGroupProps, 'isSelected' | 'onGroupChanged'> {
  /** Currently selected button. */
  values?: TypeValue[];
  /** Callback on clicked buttons. */
  onChange?: (v: TypeValue[]) => void;
}

export function MultiChoiceGroup(props: MultiChoiceGroupProps): JSX.Element {
  const { children, values, onChange } = props;

  const state = React.useState<TypeValue[]>(values || []);
  const [groupValues, setGroupValues] = state;

  const onGroupChanged = React.useCallback(
    (_e: React.MouseEvent, val?: TypeValue, ): void => {
      setGroupValues(v => {
        let newVal = [...v];
        if(val) {
          if(!v.includes(val)) newVal.push(val);
          else newVal = v.filter(e => e !== val);
        }
        return newVal;
      }
    );
  }, [setGroupValues]);

  React.useEffect(() => {
    if(onChange) onChange(groupValues);
  }, [onChange, groupValues]);

  return (
    <ButtonGroup {...props}
      isSelected={(a) => groupValues.includes(a)}
      onGroupChanged={onGroupChanged}
    >{children}</ButtonGroup>
  );
}

// --------------------------------------------------------------------------
// --- Spinner
// --------------------------------------------------------------------------

export interface SpinnerProps {
  /** Field identifier (to make forms or labels) */
  id?: string;
  /** Button tooltip */
  title?: string;
  /** Button placeholder */
  placeholder?: string;
  /** Defaults to `true`. */
  enabled?: boolean;
  /** Defaults to `false`. */
  disabled?: boolean;
  /** Currently selected value. */
  value?: number;
  /** Minimum value. */
  vmin?: number;
  /** Maximum value. */
  vmax?: number;
  /** Increment and Decrement step. */
  vstep?: number;
  /** Callback to selected values. */
  onChange?: (newValue: number) => void;
  /** Additional CSS class. */
  className?: string;
  /** Additional style for the input */
  style?: React.CSSProperties;
}

export function Spinner(props: SpinnerProps): JSX.Element {
  const { onChange } = props;
  const className = classes( 'dome-xSpinner', props.className );
  const disabled = onChange ? props.disabled : true;
  const callback = (evt: React.ChangeEvent<HTMLInputElement>): void => {
    if (onChange) {
      const newValue = Number.parseInt(evt.target.value);
      if (!Number.isNaN(newValue)) onChange(newValue);
    }
  };
  return (
    <input
      id={props.id}
      title={props.title}
      type="number"
      value={props.value}
      min={props.vmin}
      max={props.vmax}
      step={props.vstep}
      className={className}
      style={props.style}
      disabled={disabled}
      placeholder={props.placeholder}
      onChange={callback}
    />
  );
}

// --------------------------------------------------------------------------
// --- Text Input
// --------------------------------------------------------------------------

export interface FieldProps {
  /** Field identifier (to make forms or labels) */
  id?: string;
  /** Button tooltip */
  title?: string;
  /** Button placeholder */
  placeholder?: string;
  /** Defaults to `true`. */
  enabled?: boolean;
  /** Defaults to `false`. */
  disabled?: boolean;
  /** Defaults to `false`. */
  autoFocus?: boolean;
  /** Currently selected value (updated on `ENTER` key) */
  value?: string;
  /** Callback on `ENTER` key. */
  onChange?: (newValue: string) => void;
  /** Callback on every modification. */
  onEdited?: (tmpValue: string) => void;
  /** Additional CSS class. */
  className?: string;
  /** Additional style for the input */
  style?: React.CSSProperties;
}

/**
   Text Field.
*/
export const Field = (props: FieldProps): JSX.Element => {
  const { className = '', onChange, onEdited, value = '' } = props;
  const [current, setCurrent] = React.useState<string>(value);
  const disabled = onChange ? props.disabled : true;
  const ONCHANGE = (evt: React.ChangeEvent<HTMLInputElement>): void => {
    const text = evt.target.value || '';
    setCurrent(text);
    if (onEdited) onEdited(text);
  };
  const ONKEYPRESS = (evt: React.KeyboardEvent): void => {
    switch (evt.key) {
      case 'Enter':
        if (onChange) onChange(current);
        break;
      case 'Escape':
        setCurrent(value);
        if (onChange) onChange(value);
        break;
      default:
        break;
    }
  };
  return (
    <input
      id={props.id}
      type="text"
      autoFocus={!disabled && props.autoFocus}
      value={current}
      className={`dome - xField ${className} `}
      style={props.style}
      disabled={disabled}
      placeholder={props.placeholder}
      onKeyDown={ONKEYPRESS}
      onChange={ONCHANGE}
    />
  );
};

// --------------------------------------------------------------------------
// --- Selector
// --------------------------------------------------------------------------

export interface SelectProps {
  /** Field identifier (to make forms or labels) */
  id?: string;
  /** Button placeholder */
  placeholder?: string;
  /** Button tooltip */
  title?: string;
  /** Defaults to `false`. */
  disabled?: boolean;
  /** Currently selected value. */
  value?: string;
  /** Keep focus when selected (default to false). */
  focus?: boolean;
  /** Callback to selected values. */
  onChange?: (newValue?: string) => void;
  /** Additional CSS class. */
  className?: string;
  /** Additional style for the `<select/> ` container*/
  style?: React.CSSProperties;
  /** Shall be standard `<option/>` and `<optgroup/>` elements. */
  children?: React.ReactNode;
}

/**
   Menu Button.

   The different options shall be specified with HTML
   `< option/>` and `<optgroup/>` elements.
   Options and group shall be specified as follows:

     - `<optgroup label='…'>…</optgroup>`
     - `<option value='…' disabled=… >…</option>`

 */
export function Select(props: SelectProps): JSX.Element {
  const { onChange, placeholder, focus=false } = props;
  const className = classes(
    'dome-xSelect dome-xBoxButton dome-xButton-default',
    props.className,
  );
  const disabled = onChange ? props.disabled : true;
  const callback = (evt: React.ChangeEvent<HTMLSelectElement>): void => {
    if (onChange) onChange(evt.target.value);
    const target = evt.target;
    if (!focus) setImmediate(() => target.blur());
  };
  return (
    <select
      id={props.id}
      disabled={disabled}
      className={className}
      style={props.style}
      title={props.title}
      value={props.value}
      onChange={callback}
    >
      {placeholder && <option value="">— {placeholder} —</option>}
      {props.children}
    </select >
  );
}
